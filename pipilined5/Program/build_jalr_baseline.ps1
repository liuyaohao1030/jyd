Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BasePc = [long]2147483648
$Items = [System.Collections.Generic.List[object]]::new()
$Labels = @{}

function Add-Label {
    param([string]$Name)

    if ($Labels.ContainsKey($Name)) {
        throw "Duplicate label: $Name"
    }
    $Labels[$Name] = $Items.Count
}

function Add-Item {
    param([hashtable]$Fields)

    $Items.Add([pscustomobject]$Fields)
}

function Encode-I {
    param(
        [int]$Imm,
        [int]$Rs1,
        [int]$Funct3,
        [int]$Rd,
        [int]$Opcode
    )

    $word = (($Imm -band 0xfff) -shl 20) -bor
            (($Rs1 -band 0x1f) -shl 15) -bor
            (($Funct3 -band 0x7) -shl 12) -bor
            (($Rd -band 0x1f) -shl 7) -bor
            ($Opcode -band 0x7f)
    return [uint32](([int64]$word) -band [int64]4294967295)
}

function Encode-U {
    param(
        [long]$Imm20,
        [int]$Rd,
        [int]$Opcode
    )

    $word = (($Imm20 -band 0xfffff) -shl 12) -bor
            (($Rd -band 0x1f) -shl 7) -bor
            ($Opcode -band 0x7f)
    return [uint32](([int64]$word) -band [int64]4294967295)
}

function Encode-S {
    param(
        [int]$Imm,
        [int]$Rs2,
        [int]$Rs1,
        [int]$Funct3,
        [int]$Opcode
    )

    $imm12 = $Imm -band 0xfff
    $word = ((($imm12 -shr 5) -band 0x7f) -shl 25) -bor
            (($Rs2 -band 0x1f) -shl 20) -bor
            (($Rs1 -band 0x1f) -shl 15) -bor
            (($Funct3 -band 0x7) -shl 12) -bor
            (($imm12 -band 0x1f) -shl 7) -bor
            ($Opcode -band 0x7f)
    return [uint32](([int64]$word) -band [int64]4294967295)
}

function Encode-B {
    param(
        [int]$Offset,
        [int]$Rs2,
        [int]$Rs1,
        [int]$Funct3,
        [int]$Opcode
    )

    if (($Offset -band 1) -ne 0 -or $Offset -lt -4096 -or $Offset -gt 4094) {
        throw "B-type offset out of range: $Offset"
    }
    $imm13 = $Offset -band 0x1fff
    $word = ((($imm13 -shr 12) -band 0x1) -shl 31) -bor
            ((($imm13 -shr 5) -band 0x3f) -shl 25) -bor
            (($Rs2 -band 0x1f) -shl 20) -bor
            (($Rs1 -band 0x1f) -shl 15) -bor
            (($Funct3 -band 0x7) -shl 12) -bor
            ((($imm13 -shr 1) -band 0xf) -shl 8) -bor
            ((($imm13 -shr 11) -band 0x1) -shl 7) -bor
            ($Opcode -band 0x7f)
    return [uint32](([int64]$word) -band [int64]4294967295)
}

function Encode-J {
    param(
        [int]$Offset,
        [int]$Rd,
        [int]$Opcode
    )

    if (($Offset -band 1) -ne 0 -or
        $Offset -lt -1048576 -or $Offset -gt 1048574) {
        throw "J-type offset out of range: $Offset"
    }
    $imm21 = $Offset -band 0x1fffff
    $word = ((($imm21 -shr 20) -band 0x1) -shl 31) -bor
            ((($imm21 -shr 1) -band 0x3ff) -shl 21) -bor
            ((($imm21 -shr 11) -band 0x1) -shl 20) -bor
            ((($imm21 -shr 12) -band 0xff) -shl 12) -bor
            (($Rd -band 0x1f) -shl 7) -bor
            ($Opcode -band 0x7f)
    return [uint32](([int64]$word) -band [int64]4294967295)
}

function Emit-Raw {
    param([uint32]$Word, [string]$Asm)
    Add-Item @{ Kind = "raw"; Word = $Word; Asm = $Asm }
}

function Emit-I {
    param(
        [int]$Imm,
        [int]$Rs1,
        [int]$Funct3,
        [int]$Rd,
        [int]$Opcode,
        [string]$Asm
    )
    Emit-Raw (Encode-I $Imm $Rs1 $Funct3 $Rd $Opcode) $Asm
}

function Emit-U {
    param(
        [long]$Imm20,
        [int]$Rd,
        [int]$Opcode,
        [string]$Asm
    )
    Emit-Raw (Encode-U $Imm20 $Rd $Opcode) $Asm
}

function Emit-S {
    param(
        [int]$Imm,
        [int]$Rs2,
        [int]$Rs1,
        [int]$Funct3,
        [int]$Opcode,
        [string]$Asm
    )
    Emit-Raw (Encode-S $Imm $Rs2 $Rs1 $Funct3 $Opcode) $Asm
}

function Emit-Branch {
    param(
        [int]$Rs1,
        [int]$Rs2,
        [int]$Funct3,
        [string]$Target,
        [string]$Asm
    )
    Add-Item @{
        Kind = "branch"; Word = [uint32]0; Asm = $Asm
        Rs1 = $Rs1; Rs2 = $Rs2; Funct3 = $Funct3; Target = $Target
    }
}

function Emit-Jal {
    param([int]$Rd, [string]$Target, [string]$Asm)
    Add-Item @{
        Kind = "jal"; Word = [uint32]0; Asm = $Asm
        Rd = $Rd; Target = $Target
    }
}

function Emit-La {
    param([int]$Rd, [string]$Target)
    Add-Item @{
        Kind = "la_hi"; Word = [uint32]0
        Asm = "lui x$Rd, %hi($Target)"; Rd = $Rd; Target = $Target
    }
    Add-Item @{
        Kind = "la_lo"; Word = [uint32]0
        Asm = "addi x$Rd, x$Rd, %lo($Target)"; Rd = $Rd; Target = $Target
    }
}

function Emit-Nop {
    Emit-I 0 0 0 0 0x13 "nop"
}

function Pad-ToOffset {
    param([int]$Offset)

    if (($Offset -band 3) -ne 0) {
        throw "Unaligned pad offset: $Offset"
    }
    while (($Items.Count * 4) -lt $Offset) {
        Emit-Nop
    }
    if (($Items.Count * 4) -ne $Offset) {
        throw ("Program already passed offset 0x{0:x}: current 0x{1:x}" -f
               $Offset, ($Items.Count * 4))
    }
}

# RV32I opcodes and branch funct3 values used by the workload.
$OpImm = 0x13
$OpStore = 0x23
$OpBranch = 0x63
$OpJalr = 0x67
$OpJal = 0x6f
$OpLui = 0x37
$F3Add = 0
$F3And = 7
$F3Sw = 2
$F3Beq = 0
$F3Bne = 1
$F3Blt = 4

# Keep the terminal instruction at 0x80000014 to match the generic
# KLDJ_branch_perf_tb terminal detector.
Emit-Jal 0 "main" "jal x0, main"
Emit-Nop
Emit-Nop
Emit-Nop
Emit-Nop
Add-Label "terminal"
Emit-Jal 0 "terminal" "jal x0, terminal"
Emit-Nop
Emit-Nop

Add-Label "main"

# Phase 1: one stable indirect call target and one stable return target.
Emit-I 0    0  $F3Add 2  $OpImm "addi x2, x0, 0"
Emit-I 1024 0  $F3Add 3  $OpImm "addi x3, x0, 1024"
Emit-I 0    0  $F3Add 4  $OpImm "addi x4, x0, 0"
Emit-La 5 "stable_fn"
Add-Label "stable_loop"
Emit-I 0 5 $F3Add 1 $OpJalr "jalr x1, 0(x5)"
Emit-I 1 2 $F3Add 2 $OpImm  "addi x2, x2, 1"
Emit-Branch 2 3 $F3Blt "stable_loop" "blt x2, x3, stable_loop"

# Phase 2: one indirect call PC alternates between two targets.
Emit-I 0    0 $F3Add 7  $OpImm "addi x7, x0, 0"
Emit-I 1024 0 $F3Add 8  $OpImm "addi x8, x0, 1024"
Emit-I 0    0 $F3Add 17 $OpImm "addi x17, x0, 0"
Emit-La 14 "multi_a_fn"
Emit-La 15 "multi_b_fn"
Add-Label "multi_loop"
Emit-I 1 7 $F3Add 7 $OpImm "addi x7, x7, 1"
Emit-I 1 7 $F3And 6 $OpImm "andi x6, x7, 1"
Emit-Branch 6 0 $F3Beq "multi_use_b" "beq x6, x0, multi_use_b"
Emit-I 0 14 $F3Add 5 $OpImm "addi x5, x14, 0"
Emit-Jal 0 "multi_dispatch" "jal x0, multi_dispatch"
Add-Label "multi_use_b"
Emit-I 0 15 $F3Add 5 $OpImm "addi x5, x15, 0"
Add-Label "multi_dispatch"
Emit-I 0 5 $F3Add 1 $OpJalr "jalr x1, 0(x5)"
Emit-Branch 7 8 $F3Blt "multi_loop" "blt x7, x8, multi_loop"

# Phase 3: two stable call PCs share one RET instruction. The return target
# alternates, exposing the limitation of BTB-only return prediction.
Emit-I 0    0 $F3Add 18 $OpImm "addi x18, x0, 0"
Emit-I 0    0 $F3Add 20 $OpImm "addi x20, x0, 0"
Emit-I 1024 0 $F3Add 21 $OpImm "addi x21, x0, 1024"
Emit-La 19 "shared_fn"
Add-Label "shared_loop"
Emit-I 1 20 $F3Add 20 $OpImm "addi x20, x20, 1"
Emit-I 1 20 $F3And 6 $OpImm "andi x6, x20, 1"
Emit-Branch 6 0 $F3Beq "shared_even_call" "beq x6, x0, shared_even_call"
Emit-I 0 19 $F3Add 1 $OpJalr "jalr x1, 0(x19)"
Emit-Jal 0 "shared_after_call" "jal x0, shared_after_call"
Add-Label "shared_even_call"
Emit-I 0 19 $F3Add 1 $OpJalr "jalr x1, 0(x19)"
Add-Label "shared_after_call"
Emit-Branch 20 21 $F3Blt "shared_loop" "blt x20, x21, shared_loop"

# Architectural self-checks. Success values are x4=1024, x17=5120,
# and x18=1024. The status word makes failures visible in DRAM.
Emit-Branch 4 3 $F3Bne "fail" "bne x4, x3, fail"
Emit-U 0x1 22 $OpLui "lui x22, 0x1"
Emit-I 0x400 22 $F3Add 22 $OpImm "addi x22, x22, 0x400"
Emit-Branch 17 22 $F3Bne "fail" "bne x17, x22, fail"
Emit-Branch 18 21 $F3Bne "fail" "bne x18, x21, fail"

Add-Label "success"
Emit-U 0x80100 9 $OpLui "lui x9, 0x80100"
Emit-U 0x4a4c5 23 $OpLui "lui x23, 0x4a4c5"
Emit-I 1 23 $F3Add 23 $OpImm "addi x23, x23, 1"
Emit-S 0  4  9 $F3Sw $OpStore "sw x4, 0(x9)"
Emit-S 4  17 9 $F3Sw $OpStore "sw x17, 4(x9)"
Emit-S 8  18 9 $F3Sw $OpStore "sw x18, 8(x9)"
Emit-S 12 23 9 $F3Sw $OpStore "sw x23, 12(x9)"
Emit-Jal 0 "terminal" "jal x0, terminal"

Add-Label "fail"
Emit-U 0x80100 9 $OpLui "lui x9, 0x80100"
Emit-U 0xbad00 23 $OpLui "lui x23, 0xbad00"
Emit-I 1 23 $F3Add 23 $OpImm "addi x23, x23, 1"
Emit-S 0  4  9 $F3Sw $OpStore "sw x4, 0(x9)"
Emit-S 4  17 9 $F3Sw $OpStore "sw x17, 4(x9)"
Emit-S 8  18 9 $F3Sw $OpStore "sw x18, 8(x9)"
Emit-S 12 23 9 $F3Sw $OpStore "sw x23, 12(x9)"
Emit-Jal 0 "terminal" "jal x0, terminal"

# Fixed function placement keeps indirect target addresses easy to inspect.
Pad-ToOffset 0x200
Add-Label "stable_fn"
Emit-I 1 4 $F3Add 4 $OpImm "addi x4, x4, 1"
Emit-I 0 1 $F3Add 0 $OpJalr "jalr x0, 0(x1)"

Pad-ToOffset 0x210
Add-Label "multi_a_fn"
Emit-I 3 17 $F3Add 17 $OpImm "addi x17, x17, 3"
Emit-I 0 1 $F3Add 0 $OpJalr "jalr x0, 0(x1)"

Pad-ToOffset 0x220
Add-Label "multi_b_fn"
Emit-I 7 17 $F3Add 17 $OpImm "addi x17, x17, 7"
Emit-I 0 1 $F3Add 0 $OpJalr "jalr x0, 0(x1)"

Pad-ToOffset 0x230
Add-Label "shared_fn"
Emit-I 1 18 $F3Add 18 $OpImm "addi x18, x18, 1"
Emit-I 0 1 $F3Add 0 $OpJalr "jalr x0, 0(x1)"

# Resolve labels and pseudo-instructions.
for ($index = 0; $index -lt $Items.Count; $index++) {
    $item = $Items[$index]
    $pc = $BasePc + ($index * 4)

    if ($item.Kind -eq "raw") {
        continue
    }
    if (-not $Labels.ContainsKey($item.Target)) {
        throw "Undefined label: $($item.Target)"
    }

    $targetAddress = $BasePc + ([int]$Labels[$item.Target] * 4)
    switch ($item.Kind) {
        "branch" {
            $offset = [int]($targetAddress - $pc)
            $item.Word = Encode-B $offset $item.Rs2 $item.Rs1 $item.Funct3 $OpBranch
        }
        "jal" {
            $offset = [int]($targetAddress - $pc)
            $item.Word = Encode-J $offset $item.Rd $OpJal
        }
        "la_hi" {
            $upper = (($targetAddress + 0x800) -shr 12) -band 0xfffff
            $item.Word = Encode-U $upper $item.Rd $OpLui
        }
        "la_lo" {
            $lower = [int]($targetAddress -
                     ([long]((($targetAddress + 0x800) -shr 12) -band 0xfffff) -shl 12))
            $item.Word = Encode-I $lower $item.Rd $F3Add $item.Rd $OpImm
        }
        default {
            throw "Unknown item kind: $($item.Kind)"
        }
    }
}

$OutputDir = $PSScriptRoot
$IromPath = Join-Path $OutputDir "jalr_baseline_irom.txt"
$DramPath = Join-Path $OutputDir "jalr_baseline_dram.txt"
$ListingPath = Join-Path $OutputDir "jalr_baseline.lst"

$iromLines = [System.Collections.Generic.List[string]]::new()
$iromLines.Add("memory_initialization_radix=16;")
$iromLines.Add("memory_initialization_vector=")
for ($index = 0; $index -lt $Items.Count; $index++) {
    $suffix = if ($index -eq $Items.Count - 1) { ";" } else { "," }
    $iromLines.Add(("{0:x8}{1}" -f ([uint32]$Items[$index].Word), $suffix))
}
[System.IO.File]::WriteAllLines($IromPath, $iromLines)

$dramLines = @(
    "memory_initialization_radix=16;",
    "memory_initialization_vector=",
    "00000000,",
    "00000000,",
    "00000000,",
    "00000000;"
)
[System.IO.File]::WriteAllLines($DramPath, $dramLines)

$labelsByIndex = @{}
foreach ($entry in $Labels.GetEnumerator()) {
    $labelIndex = [int]$entry.Value
    if (-not $labelsByIndex.ContainsKey($labelIndex)) {
        $labelsByIndex[$labelIndex] = [System.Collections.Generic.List[string]]::new()
    }
    $labelsByIndex[$labelIndex].Add([string]$entry.Key)
}

$listingLines = [System.Collections.Generic.List[string]]::new()
$listingLines.Add("KLDJ JALR baseline workload")
$listingLines.Add("Expected retired instructions: 21536")
$listingLines.Add("Expected conditional branches: 5123 (taken 4093)")
$listingLines.Add("Expected JALR: 6144 (RET 3072)")
$listingLines.Add("Expected success DRAM: 00000400 00001400 00000400 4a4c5001")
$listingLines.Add("")
for ($index = 0; $index -lt $Items.Count; $index++) {
    if ($labelsByIndex.ContainsKey($index)) {
        foreach ($labelName in ($labelsByIndex[$index] | Sort-Object)) {
            $listingLines.Add("${labelName}:")
        }
    }
    $pc = [uint32]($BasePc + ($index * 4))
    $listingLines.Add(("{0:x8}: {1:x8}    {2}" -f
                       $pc, ([uint32]$Items[$index].Word), $Items[$index].Asm))
}
[System.IO.File]::WriteAllLines($ListingPath, $listingLines)

Write-Host ("Generated {0} instructions" -f $Items.Count)
Write-Host $IromPath
Write-Host $DramPath
Write-Host $ListingPath
