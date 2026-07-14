param(
    [ValidateSet('rv32i', 'dram-driver')]
    [string]$Test = 'rv32i'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RtlDir = Join-Path $ScriptDir 'sources_1/imports/rtl'
$TbDir = Join-Path $ScriptDir 'sim_1/imports/sim'
$BuildDir = Join-Path $ScriptDir 'build'

foreach ($tool in @('xvlog', 'xelab', 'xsim')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Vivado simulator tool '$tool' was not found in PATH"
    }
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

if ($Test -eq 'rv32i') {
    $Top = 'KLDJ_top_tb'
    $Snapshot = 'mem1_mem2_regression_sim'
    $PassPattern = 'ALL TESTS PASSED'
    $Sources = @(
        Get-ChildItem -LiteralPath $RtlDir -Recurse -Filter '*.v' |
            ForEach-Object FullName
    ) + @(Join-Path $TbDir 'KLDJ_top_tb.sv')
    $CompileArgs = @(
        '--sv',
        '-i', $RtlDir,
        '-i', (Join-Path $RtlDir 'alu'),
        '-i', (Join-Path $RtlDir 'pipe'),
        '-i', (Join-Path $RtlDir 'stage'),
        '-i', (Join-Path $RtlDir 'util')
    ) + $Sources
} else {
    $Top = 'dram_driver_tb'
    $Snapshot = 'dram_driver_regression_sim'
    $PassPattern = 'DRAM DRIVER TEST PASSED'
    $Sources = @(
        (Join-Path $ScriptDir '../new/DRAM_TDP.sv'),
        (Join-Path $ScriptDir '../new/dram_driver.sv'),
        (Join-Path $TbDir 'dram_driver_tb.sv')
    )
    $CompileArgs = @('--sv') + $Sources
}

$LogPath = Join-Path $BuildDir "$Test.xsim.log"

Push-Location $ScriptDir
try {
    & xvlog @CompileArgs
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed for $Test"
    }

    & xelab $Top '-s' $Snapshot '--debug' 'typical'
    if ($LASTEXITCODE -ne 0) {
        throw "xelab failed for $Test"
    }

    $SimOutput = @(& xsim $Snapshot '-runall' 2>&1)
    $SimExitCode = $LASTEXITCODE
    $SimOutput | Tee-Object -FilePath $LogPath
    $OutputText = $SimOutput -join [Environment]::NewLine

    if (($SimExitCode -ne 0) -or
        ($OutputText -notmatch [regex]::Escape($PassPattern)) -or
        ($OutputText -match 'SOME TESTS FAILED|\[FAIL\]|\[TIMEOUT\]|FATAL_ERROR')) {
        throw "$Test simulation failed; see $LogPath"
    }

    Write-Host "PASS: $Test ($LogPath)"
}
finally {
    Pop-Location
}
