#!/usr/bin/env python3
"""Create board-test IROM images for one RV32 Zb extension at a time.

The source demo/irom-v2.coe is never edited.  Every generated image patches
only reset word 0 to jump to a small self-test stored in unused IROM space.
On success the self-test shows a group-specific code on LED/SEG, optionally
holds it for board observation, restores the reset-visible GPR state, and
resumes the original image at 0x8000_0004.
On failure it leaves a group/test-index failure code displayed forever.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Callable, Dict, List, Tuple


BASE_PC = 0x8000_0000
TEST_WORD = 0x900  # 0x8000_2400; outside the 2,216-word demo image.
TEST_PC = BASE_PC + TEST_WORD * 4
NOP = 0x0000_0013
SOURCE_SHA256 = "0cea80f2ca36e2672ac8d1e3d0087f88dc24b5a33a177c74b47330b0637c6a1b"

# The CPU clock is 200 MHz in the production board build.  The loop takes at
# least one visible fraction of a second (normally about one second) without
# affecting the original demo after it resumes.
PASS_HOLD_ITERATIONS = 100_000_000

GROUPS: Dict[str, int] = {
    "zba": 1,
    "zbb": 2,
    "zbc": 3,
    "zbs": 4,
    "zbkb": 5,
    "zbkx": 6,
}

# Register choices are deliberately caller-saved, then all GPRs are cleared
# before the original startup sequence resumes.
LED_BASE = 5
RS1 = 6
RS2 = 7
RS3 = 8
RESULT = 9
EXPECTED = 10


def i_type(imm: int, rs1: int, funct3: int, rd: int, opcode: int = 0x13) -> int:
    if not -2048 <= imm <= 2047:
        raise ValueError(f"I-type immediate out of range: {imm}")
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def r_type(funct7: int, rs2: int, rs1: int, funct3: int, rd: int) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x33


def s_type(imm: int, rs2: int, rs1: int, funct3: int = 0b010) -> int:
    if not -2048 <= imm <= 2047:
        raise ValueError(f"S-type immediate out of range: {imm}")
    encoded = imm & 0xFFF
    return (((encoded >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | ((encoded & 0x1F) << 7) | 0x23


def b_type(delta: int, rs2: int, rs1: int, funct3: int = 0b001) -> int:
    if delta & 1 or not -4096 <= delta <= 4094:
        raise ValueError(f"B-type target out of range: {delta}")
    encoded = delta & 0x1FFF
    return (((encoded >> 12) & 0x1) << 31) | (((encoded >> 5) & 0x3F) << 25) | \
           (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | \
           (((encoded >> 1) & 0xF) << 8) | (((encoded >> 11) & 0x1) << 7) | 0x63


def j_type(delta: int, rd: int = 0) -> int:
    if delta & 1 or not -(1 << 20) <= delta <= (1 << 20) - 2:
        raise ValueError(f"J-type target out of range: {delta}")
    encoded = delta & 0x1F_FFFF
    return (((encoded >> 20) & 0x1) << 31) | (((encoded >> 1) & 0x3FF) << 21) | \
           (((encoded >> 11) & 0x1) << 20) | (((encoded >> 12) & 0xFF) << 12) | \
           (rd << 7) | 0x6F


def u_type(imm20: int, rd: int) -> int:
    return ((imm20 & 0xF_FFFF) << 12) | (rd << 7) | 0x37


class Assembler:
    def __init__(self, base_pc: int) -> None:
        self.base_pc = base_pc
        self.words: List[int] = []
        self.labels: Dict[str, int] = {}
        self.fixups: List[Tuple[str, int, int, int, str]] = []

    @property
    def pc(self) -> int:
        return self.base_pc + len(self.words) * 4

    def emit(self, word: int) -> None:
        self.words.append(word & 0xFFFF_FFFF)

    def label(self, name: str) -> None:
        if name in self.labels:
            raise ValueError(f"duplicate label: {name}")
        self.labels[name] = self.pc

    def li(self, rd: int, value: int) -> None:
        value &= 0xFFFF_FFFF
        signed_value = value if value < 0x8000_0000 else value - 0x1_0000_0000
        if -2048 <= signed_value <= 2047:
            self.emit(i_type(signed_value, 0, 0b000, rd))
            return
        upper = (signed_value + 0x800) >> 12
        lower = signed_value - (upper << 12)
        self.emit(u_type(upper, rd))
        self.emit(i_type(lower, rd, 0b000, rd))

    def bne(self, rs1: int, rs2: int, target: str) -> None:
        index = len(self.words)
        self.emit(0)
        self.fixups.append(("bne", index, rs1, rs2, target))

    def jal(self, rd: int, target: str) -> None:
        index = len(self.words)
        self.emit(0)
        self.fixups.append(("jal", index, rd, 0, target))

    def jal_absolute(self, rd: int, target_pc: int) -> None:
        self.emit(j_type(target_pc - self.pc, rd))

    def resolve(self) -> None:
        for kind, index, first, second, target in self.fixups:
            if target not in self.labels:
                raise ValueError(f"undefined label: {target}")
            origin = self.base_pc + index * 4
            delta = self.labels[target] - origin
            if kind == "bne":
                self.words[index] = b_type(delta, second, first)
            elif kind == "jal":
                self.words[index] = j_type(delta, first)
            else:
                raise ValueError(f"unsupported fixup: {kind}")


def parse_coe(path: Path) -> List[int]:
    words: List[int] = []
    in_vector = False
    for raw_line in path.read_text(encoding="ascii").splitlines():
        line = raw_line.strip()
        if not in_vector:
            if line.lower().startswith("memory_initialization_vector"):
                in_vector = True
            continue
        if not line:
            continue
        token = line.rstrip(",;").strip()
        if not token:
            continue
        if not re.fullmatch(r"[0-9a-fA-F]+", token):
            raise ValueError(f"invalid COE word {token!r} in {path}")
        words.append(int(token, 16))
    if not in_vector or not words:
        raise ValueError(f"no memory_initialization_vector in {path}")
    return words


def write_coe(path: Path, words: List[int]) -> None:
    lines = ["memory_initialization_radix=16;", "memory_initialization_vector="]
    for index, word in enumerate(words):
        suffix = ";" if index == len(words) - 1 else ","
        lines.append(f"{word:08x}{suffix}")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def emit_check(
    asm: Assembler,
    tests: List[str],
    name: str,
    emit_instruction: Callable[[], None],
    expected: int,
) -> None:
    emit_instruction()
    tests.append(name)
    asm.li(EXPECTED, expected)
    asm.bne(RESULT, EXPECTED, f"fail_{len(tests)}")


def emit_group_tests(asm: Assembler, group: str) -> List[str]:
    tests: List[str] = []

    def r(funct7: int, rs2: int, rs1: int, funct3: int) -> Callable[[], None]:
        return lambda: asm.emit(r_type(funct7, rs2, rs1, funct3, RESULT))

    def i(imm: int, rs1: int, funct3: int) -> Callable[[], None]:
        return lambda: asm.emit(i_type(imm, rs1, funct3, RESULT))

    if group == "zba":
        asm.li(RS1, 0x1234_5678)
        asm.li(RS2, 0x0102_0304)
        emit_check(asm, tests, "sh1add", r(0b0010000, RS2, RS1, 0b010), 0x256A_AFF4)
        emit_check(asm, tests, "sh2add", r(0b0010000, RS2, RS1, 0b100), 0x49D3_5CE4)
        emit_check(asm, tests, "sh3add", r(0b0010000, RS2, RS1, 0b110), 0x92A4_B6C4)

    elif group == "zbb":
        asm.li(RS1, 0x8001_00F0)
        asm.li(RS2, 0x7FFF_0F0F)
        asm.li(RS3, 0x0010_8001)
        emit_check(asm, tests, "andn",   r(0b0100000, RS2, RS1, 0b111), 0x8000_00F0)
        emit_check(asm, tests, "orn",    r(0b0100000, RS2, RS1, 0b110), 0x8001_F0F0)
        emit_check(asm, tests, "xnor",   r(0b0100000, RS2, RS1, 0b100), 0x0001_F000)
        emit_check(asm, tests, "clz",    i(0x600, RS3, 0b001), 0x0000_000B)
        emit_check(asm, tests, "ctz",    i(0x601, RS3, 0b001), 0x0000_0000)
        emit_check(asm, tests, "cpop",   i(0x602, RS3, 0b001), 0x0000_0003)
        emit_check(asm, tests, "max",    r(0b0000101, RS2, RS1, 0b110), 0x7FFF_0F0F)
        emit_check(asm, tests, "maxu",   r(0b0000101, RS2, RS1, 0b111), 0x8001_00F0)
        emit_check(asm, tests, "min",    r(0b0000101, RS2, RS1, 0b100), 0x8001_00F0)
        emit_check(asm, tests, "minu",   r(0b0000101, RS2, RS1, 0b101), 0x7FFF_0F0F)
        emit_check(asm, tests, "sext.b", i(0x604, RS3, 0b001), 0x0000_0001)
        emit_check(asm, tests, "sext.h", i(0x605, RS3, 0b001), 0xFFFF_8001)
        emit_check(asm, tests, "zext.h", r(0b0000100, 0, RS3, 0b100), 0x0000_8001)
        emit_check(asm, tests, "rol",    r(0b0110000, RS2, RS1, 0b001), 0x8078_4000)
        emit_check(asm, tests, "ror",    r(0b0110000, RS2, RS1, 0b101), 0x01E1_0002)
        emit_check(asm, tests, "rori",   i(0x607, RS1, 0b101), 0xE100_0201)
        emit_check(asm, tests, "orc.b",  i(0x287, RS1, 0b101), 0xFFFF_00FF)
        emit_check(asm, tests, "rev8",   i(0x698, RS1, 0b101), 0xF000_0180)

    elif group == "zbc":
        asm.li(RS1, 0x1234_5678)
        asm.li(RS2, 0x9ABC_DEF0)
        emit_check(asm, tests, "clmul",  r(0b0000101, RS2, RS1, 0b001), 0x5CD2_5A80)
        emit_check(asm, tests, "clmulh", r(0b0000101, RS2, RS1, 0b011), 0x0886_0E94)
        emit_check(asm, tests, "clmulr", r(0b0000101, RS2, RS1, 0b010), 0x110C_1D28)

    elif group == "zbs":
        asm.li(RS1, 0x8000_0011)
        asm.li(RS2, 31)
        emit_check(asm, tests, "bset",  r(0b0010100, RS2, RS1, 0b001), 0x8000_0011)
        emit_check(asm, tests, "bclr",  r(0b0100100, RS2, RS1, 0b001), 0x0000_0011)
        emit_check(asm, tests, "binv",  r(0b0110100, RS2, RS1, 0b001), 0x0000_0011)
        emit_check(asm, tests, "bext",  r(0b0100100, RS2, RS1, 0b101), 0x0000_0001)
        emit_check(asm, tests, "bseti", i(0x285, RS1, 0b001), 0x8000_0031)
        emit_check(asm, tests, "bclri", i(0x49F, RS1, 0b001), 0x0000_0011)
        emit_check(asm, tests, "binvi", i(0x680, RS1, 0b001), 0x8000_0010)
        emit_check(asm, tests, "bexti", i(0x484, RS1, 0b101), 0x0000_0001)

    elif group == "zbkb":
        asm.li(RS1, 0x89AB_CDEF)
        asm.li(RS2, 0x1357_9BDF)
        emit_check(asm, tests, "andn",   r(0b0100000, RS2, RS1, 0b111), 0x88A8_4420)
        emit_check(asm, tests, "orn",    r(0b0100000, RS2, RS1, 0b110), 0xEDAB_EDEF)
        emit_check(asm, tests, "xnor",   r(0b0100000, RS2, RS1, 0b100), 0x6503_A9CF)
        emit_check(asm, tests, "rol",    r(0b0110000, RS2, RS1, 0b001), 0xC4D5_E6F7)
        emit_check(asm, tests, "ror",    r(0b0110000, RS2, RS1, 0b101), 0x1357_9BDF)
        emit_check(asm, tests, "rori",   i(0x607, RS1, 0b101), 0xDF13_579B)
        emit_check(asm, tests, "rev8",   i(0x698, RS1, 0b101), 0xEFCD_AB89)
        emit_check(asm, tests, "brev8",  i(0x687, RS1, 0b101), 0x91D5_B3F7)
        emit_check(asm, tests, "pack",   r(0b0000100, RS2, RS1, 0b100), 0x9BDF_CDEF)
        emit_check(asm, tests, "packh",  r(0b0000100, RS2, RS1, 0b111), 0x0000_DFEF)
        emit_check(asm, tests, "zip",    i(0x08F, RS1, 0b001), 0xD0D3_DCDF)
        emit_check(asm, tests, "unzip",  i(0x08F, RS1, 0b101), 0xAFAF_11BB)

    elif group == "zbkx":
        asm.li(RS1, 0x0123_4567)
        asm.li(RS2, 0x7654_3210)
        asm.li(RS3, 0x0302_0100)
        emit_check(asm, tests, "xperm4", r(0b0010100, RS2, RS1, 0b010), 0x0123_4567)
        emit_check(asm, tests, "xperm8", r(0b0010100, RS3, RS1, 0b100), 0x0123_4567)

    else:
        raise ValueError(f"unsupported group: {group}")

    return tests


def emit_mmio_code(asm: Assembler, code: int) -> None:
    # LED is 0x8020_0040 and SEG is 0x8020_0020 in perip_bridge.sv.
    asm.li(LED_BASE, 0x8020_0040)
    asm.li(RS1, code)
    asm.emit(s_type(0, RS1, LED_BASE))
    asm.emit(i_type(-0x20, LED_BASE, 0b000, LED_BASE))
    asm.emit(s_type(0, RS1, LED_BASE))


def build_test_program(
    group: str, pass_hold_iterations: int = PASS_HOLD_ITERATIONS
) -> Tuple[List[int], List[str], int, Dict[str, int]]:
    if pass_hold_iterations < 0:
        raise ValueError("pass_hold_iterations must not be negative")
    group_id = GROUPS[group]
    asm = Assembler(TEST_PC)
    tests = emit_group_tests(asm, group)
    pass_led = 0x5A5A_0000 | group_id

    emit_mmio_code(asm, pass_led)
    # A zero hold is useful for a board diagnostic: it proves that the
    # self-test can return to the demo without exercising a long tight loop.
    if pass_hold_iterations != 0:
        asm.li(LED_BASE, pass_hold_iterations)
        asm.label("pass_hold")
        asm.emit(i_type(-1, LED_BASE, 0b000, LED_BASE))
        asm.bne(LED_BASE, 0, "pass_hold")

    # Recreate the architecture-visible reset state expected by the original
    # startup.  The replaced AUIPC at 0x8000_0000 set sp to 0x8012_1000;
    # the original ADDI at 0x8000_0004 then adds 0x50.
    for register in range(1, 32):
        if register != 2:
            asm.emit(i_type(0, 0, 0b000, register))
    asm.emit(u_type(0x80121, 2))
    asm.jal_absolute(0, BASE_PC + 4)

    for index, _name in enumerate(tests, start=1):
        asm.label(f"fail_{index}")
        fail_led = 0xE000_0000 | (group_id << 16) | index
        emit_mmio_code(asm, fail_led)
        asm.label(f"fail_hold_{index}")
        asm.jal(0, f"fail_hold_{index}")

    asm.resolve()
    if len(asm.words) > 4096 - TEST_WORD:
        raise ValueError(f"{group} test program exceeds available IROM space")
    return asm.words, tests, pass_led, {
        "test_start_pc": TEST_PC,
        "test_word": TEST_WORD,
        "pass_hold_iterations": pass_hold_iterations,
    }


def make_variant(
    source_words: List[int],
    group: str,
    pass_hold_iterations: int = PASS_HOLD_ITERATIONS,
) -> Tuple[List[int], List[str], int, Dict[str, int]]:
    if len(source_words) > TEST_WORD:
        raise ValueError(
            f"demo image is {len(source_words)} words, overlapping test area word {TEST_WORD}"
        )
    if source_words[0] != 0x0012_1117 or source_words[1] != 0x0501_0113:
        raise ValueError("unexpected demo startup words; refusing to patch a different program")

    program, tests, pass_led, details = build_test_program(group, pass_hold_iterations)
    image = list(source_words)
    image[0] = j_type(TEST_PC - BASE_PC, 0)
    image.extend([NOP] * (TEST_WORD - len(image)))
    image.extend(program)
    if image[1:len(source_words)] != source_words[1:]:
        raise AssertionError("a source-program word other than reset word 0 changed")
    if any(word != NOP for word in image[len(source_words):TEST_WORD]):
        raise AssertionError("test-area gap is not filled with safe NOP instructions")
    details["patched_word_index"] = 0
    details["source_words_preserved_from_index"] = 1
    details["original_word_0"] = f"0x{source_words[0]:08x}"
    details["patched_word_0"] = f"0x{image[0]:08x}"
    details["word_count"] = len(image)
    return image, tests, pass_led, details


def main() -> None:
    script_dir = Path(__file__).resolve().parent
    demo_dir = script_dir.parent
    source_path = demo_dir / "irom-v2.coe"

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--group",
        choices=["all", *GROUPS],
        default="all",
        help="generate one group or all six (default)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=script_dir,
        help="directory for generated COE files and manifest",
    )
    parser.add_argument(
        "--pass-hold-iterations",
        type=int,
        default=PASS_HOLD_ITERATIONS,
        help="success-code loop count; use 0 to return to the demo immediately",
    )
    parser.add_argument(
        "--name-suffix",
        default="",
        help="optional safe suffix before .coe, for example -quick",
    )
    args = parser.parse_args()

    if args.pass_hold_iterations < 0:
        raise SystemExit("--pass-hold-iterations must not be negative")
    if not re.fullmatch(r"(?:-[A-Za-z0-9][A-Za-z0-9_-]*)?", args.name_suffix):
        raise SystemExit("--name-suffix must be empty or look like -quick")

    source_bytes = source_path.read_bytes()
    source_hash = hashlib.sha256(source_bytes).hexdigest()
    if source_hash != SOURCE_SHA256:
        raise SystemExit(
            f"refusing to generate from an unexpected irom-v2.coe SHA-256: {source_hash}"
        )
    source_words = parse_coe(source_path)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    selected_groups = list(GROUPS) if args.group == "all" else [args.group]
    manifest = {
        "source": str(source_path.relative_to(demo_dir.parent)),
        "source_sha256": source_hash,
        "source_word_count": len(source_words),
        "base_pc": f"0x{BASE_PC:08x}",
        "variants": {},
    }

    for group in selected_groups:
        image, tests, pass_led, details = make_variant(
            source_words, group, args.pass_hold_iterations
        )
        output_path = args.output_dir / f"irom-v2-{group}{args.name_suffix}.coe"
        write_coe(output_path, image)
        if parse_coe(output_path) != image:
            raise AssertionError(f"COE round-trip verification failed: {output_path}")
        manifest["variants"][group] = {
            "coe": output_path.name,
            "group_id": GROUPS[group],
            "pass_led": f"0x{pass_led:08x}",
            "tests": tests,
            **{key: (f"0x{value:08x}" if key.endswith("pc") else value)
               for key, value in details.items()},
        }
        print(
            f"[ZB_IROM] {group}: {len(tests)} instructions, "
            f"pass LED=0x{pass_led:08x}, {output_path}"
        )

    manifest_path = args.output_dir / f"irom-v2-zb-manifest{args.name_suffix}.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[ZB_IROM] wrote {manifest_path}")


if __name__ == "__main__":
    main()
