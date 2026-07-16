param(
    [ValidateSet('all', 'ras-unit', 'ex-bpu-ctrl', 'bpu', 'ras-integration',
                 'irom-baseline', 'irom-ras', 'irom-both')]
    [string]$Test = 'all',
    [switch]$ToCompletion
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$RtlDir = Join-Path $Root 'sources_1\imports\rtl'
$TbDir = Join-Path $Root 'sim_1\imports\sim'

$Iverilog = (Get-Command iverilog -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if (-not $Iverilog -and (Test-Path -LiteralPath 'C:\iverilog\bin\iverilog.exe')) {
    $Iverilog = 'C:\iverilog\bin\iverilog.exe'
}
if (-not $Iverilog) {
    throw 'Icarus Verilog was not found. Add iverilog to PATH or install it at C:\iverilog\bin.'
}

$Vvp = Join-Path (Split-Path -Parent $Iverilog) 'vvp.exe'
if (-not (Test-Path -LiteralPath $Vvp)) {
    $Vvp = (Get-Command vvp -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
}
if (-not $Vvp) {
    throw 'The vvp runtime matching Icarus Verilog was not found.'
}

$RtlFiles = @(Get-ChildItem -LiteralPath $RtlDir -Recurse -File -Filter '*.v' |
    Sort-Object FullName |
    ForEach-Object { $_.FullName })
$IncludeArgs = @(
    '-I', $RtlDir,
    '-I', (Join-Path $RtlDir 'alu'),
    '-I', (Join-Path $RtlDir 'pipe'),
    '-I', (Join-Path $RtlDir 'stage'),
    '-I', (Join-Path $RtlDir 'util')
)
$PeripheralFiles = @(
    (Join-Path $Root '..\new\seg7.sv'),
    (Join-Path $Root '..\new\display_seg.sv'),
    (Join-Path $Root '..\new\counter.sv'),
    (Join-Path $Root '..\new\DRAM_TDP.sv'),
    (Join-Path $Root '..\new\dram_driver.sv'),
    (Join-Path $Root '..\new\perip_bridge.sv')
)

function Invoke-IcarusTest {
    param(
        [string]$Name,
        [string]$Top,
        [string]$Testbench,
        [string[]]$Defines = @(),
        [string[]]$RuntimeArgs = @(),
        [switch]$NeedsPeripherals
    )

    $Output = Join-Path $env:TEMP ("kldj_${Name}_$PID.vvp")
    $CompileArgs = @('-g2012', '-s', $Top) + $Defines + $IncludeArgs +
                   @('-o', $Output) + $RtlFiles
    if ($NeedsPeripherals) {
        $CompileArgs += $PeripheralFiles
    }
    $CompileArgs += $Testbench

    Write-Host "`n=== Compile $Name ==="
    $CompileOutput = @(& $Iverilog @CompileArgs 2>&1)
    $CompileExit = $LASTEXITCODE
    $CompileOutput | ForEach-Object { Write-Host $_ }
    if ($CompileExit -ne 0) {
        throw "Icarus compilation failed for $Name."
    }

    Write-Host "=== Simulate $Name ==="
    $SimulationOutput = @(& $Vvp $Output @RuntimeArgs 2>&1)
    $SimulationExit = $LASTEXITCODE
    $SimulationOutput | ForEach-Object { Write-Host $_ }
    if ($SimulationExit -ne 0) {
        throw "Simulation failed for $Name."
    }
    return $SimulationOutput
}

function Assert-Pass {
    param([string[]]$Lines, [string]$Pattern, [string]$Name)
    if (-not [bool]($Lines -match [regex]::Escape($Pattern))) {
        throw "$Name did not emit its pass marker '$Pattern'."
    }
}

function Invoke-Demo {
    param([switch]$Ras)

    $Defines = @('-DBENCH_SIX_STAGE')
    if ($Ras) { $Defines += '-DSIX_RAS_PRED' }
    if ($ToCompletion) { $Defines += '-DBENCH_TO_COMPLETION' }
    $Args = @(
        ('+IROM_COE=' + ((Join-Path $Root 'demo\irom-v2.coe').Replace('\', '/'))),
        ('+DRAM_COE=' + ((Join-Path $Root 'demo\dram.coe').Replace('\', '/')))
    )
    $Name = if ($Ras) { 'irom_ras' } else { 'irom_baseline' }
    $Lines = @(Invoke-IcarusTest -Name $Name -Top 'KLDJ_demo_perf_tb' `
        -Testbench (Join-Path $TbDir 'KLDJ_demo_perf_tb.sv') -Defines $Defines `
        -RuntimeArgs $Args -NeedsPeripherals)
    Assert-Pass -Lines $Lines -Pattern 'DEMO_PERF_PASS' -Name $Name
    $Result = @($Lines | Where-Object { $_ -match 'DEMO_PERF_RESULT' } | Select-Object -Last 1)
    if ($Result.Count -ne 1 -or $Result[0] -notmatch 'commit_hash=(0x[0-9a-fA-F]+)') {
        throw "$Name did not produce a parseable DEMO_PERF_RESULT."
    }
    return [PSCustomObject]@{
        Name = $Name
        Hash = $Matches[1]
        Result = $Result[0]
    }
}

switch ($Test) {
    'ras-unit' {
        $Lines = @(Invoke-IcarusTest -Name 'ras_unit' -Top 'ras_tb' `
            -Testbench (Join-Path $TbDir 'ras_tb.sv'))
        Assert-Pass $Lines 'RAS UNIT TEST PASSED' 'ras-unit'
    }
    'ex-bpu-ctrl' {
        $Lines = @(Invoke-IcarusTest -Name 'ex_bpu_ctrl' -Top 'ex_bpu_ctrl_tb' `
            -Testbench (Join-Path $TbDir 'ex_bpu_ctrl_tb.sv'))
        Assert-Pass $Lines 'PASS: ex_bpu_ctrl_tb' 'ex-bpu-ctrl'
    }
    'bpu' {
        $Lines = @(Invoke-IcarusTest -Name 'bpu' -Top 'bpu_tb' `
            -Testbench (Join-Path $TbDir 'bpu_tb.sv'))
        Assert-Pass $Lines 'BPU UNIT TEST PASSED' 'bpu'
    }
    'ras-integration' {
        $Lines = @(Invoke-IcarusTest -Name 'ras_integration' -Top 'ras_integration_tb' `
            -Testbench (Join-Path $TbDir 'ras_integration_tb.sv'))
        Assert-Pass $Lines 'RAS INTEGRATION TEST PASSED' 'ras-integration'
    }
    'irom-baseline' {
        [void](Invoke-Demo)
    }
    'irom-ras' {
        [void](Invoke-Demo -Ras)
    }
    'irom-both' {
        $Baseline = Invoke-Demo
        $Ras = Invoke-Demo -Ras
        if ($Baseline.Hash -ne $Ras.Hash) {
            throw "Architectural commit hash differs: baseline=$($Baseline.Hash), ras=$($Ras.Hash)"
        }
        Write-Host "`nPASS: irom-v2 commit hashes match ($($Ras.Hash))"
        Write-Host "Baseline: $($Baseline.Result)"
        Write-Host "RAS:      $($Ras.Result)"
    }
    'all' {
        $CompletionArgs = if ($ToCompletion) { @('-ToCompletion') } else { @() }
        foreach ($Subtest in @('ras-unit', 'ex-bpu-ctrl', 'bpu', 'ras-integration')) {
            & $PSCommandPath -Test $Subtest @CompletionArgs
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
        & $PSCommandPath -Test irom-both @CompletionArgs
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}
