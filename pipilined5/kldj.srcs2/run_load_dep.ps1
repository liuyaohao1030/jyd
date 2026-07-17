param(
    [switch]$DumpVcd
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$RtlDir = Join-Path $Root 'sources_1\imports\rtl'
$Tb = Join-Path $Root 'sim_1\imports\sim\KLDJ_load_dep_tb.sv'
$Label = 'forced_mem2_load_fwd'
$WorkDir = Join-Path $Root ("build\load_dep\{0}" -f $Label)
$Snapshot = "load_dep_${Label}_sim"

foreach ($tool in @('xvlog', 'xelab', 'xsim')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Vivado simulator tool '$tool' was not found in PATH"
    }
}
if (-not (Test-Path -LiteralPath $Tb)) {
    throw "Load-dependency testbench is missing: $Tb"
}

$RtlFiles = @(Get-ChildItem -LiteralPath $RtlDir -Recurse -File -Filter '*.v' |
    Sort-Object FullName |
    ForEach-Object { $_.FullName })
if ($RtlFiles.Count -eq 0) {
    throw "No RTL files found in $RtlDir"
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$CompileArgs = @(
    '--sv',
    '-i', $RtlDir,
    '-i', (Join-Path $RtlDir 'alu'),
    '-i', (Join-Path $RtlDir 'pipe'),
    '-i', (Join-Path $RtlDir 'stage'),
    '-i', (Join-Path $RtlDir 'util')
)
if ($DumpVcd) {
    $CompileArgs += @('-d', 'LOAD_DEP_DUMP_VCD')
}
$CompileArgs += $RtlFiles + @($Tb)

Push-Location $WorkDir
try {
    Write-Host "=== Compile load-dependency regression ($Label) ==="
    & xvlog @CompileArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'xvlog failed'
    }

    Write-Host "=== Elaborate load-dependency regression ($Label) ==="
    & xelab 'KLDJ_load_dep_tb' '-s' $Snapshot '--debug' 'typical' '--timescale' '1ns/1ps' '--relax'
    if ($LASTEXITCODE -ne 0) {
        throw 'xelab failed'
    }

    Write-Host "=== Run load-dependency regression ($Label) ==="
    $SimOutput = @(& xsim $Snapshot '--runall' 2>&1)
    $SimExitCode = $LASTEXITCODE
    $LogPath = Join-Path $WorkDir "$Label.load_dep.log"
    $SimOutput | Tee-Object -FilePath $LogPath
    $OutputText = $SimOutput -join [Environment]::NewLine
    if (($SimExitCode -ne 0) -or ($OutputText -notmatch 'LOAD_DEP_REGRESSION_PASS')) {
        throw "load-dependency regression failed; see $LogPath"
    }

    Write-Host "Load-dependency regression passed.  Log: $LogPath"
}
finally {
    Pop-Location
}
