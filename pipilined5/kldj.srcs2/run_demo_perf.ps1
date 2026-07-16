param(
    [ValidateSet('six', 'pipeline5', 'both')]
    [string]$Version = 'both',
    [switch]$SixStaticJal,
    [switch]$SixMem2LoadFwd,
    [switch]$SixRas,
    [switch]$ToCompletion,
    [switch]$DumpVcd
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Tb = Join-Path $Root 'sim_1\imports\sim\KLDJ_demo_perf_tb.sv'
$IromCoe = (Join-Path $Root 'demo\irom-v2.coe').Replace('\', '/')
$DramCoe = (Join-Path $Root 'demo\dram.coe').Replace('\', '/')
$BuildRoot = Join-Path $Root 'build\demo_perf'

foreach ($tool in @('xvlog', 'xelab', 'xsim')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Vivado simulator tool '$tool' was not found in PATH"
    }
}

$PeripheralFiles = @(
    (Join-Path $Root '..\new\seg7.sv'),
    (Join-Path $Root '..\new\display_seg.sv'),
    (Join-Path $Root '..\new\counter.sv'),
    (Join-Path $Root '..\new\DRAM_TDP.sv'),
    (Join-Path $Root '..\new\dram_driver.sv'),
    (Join-Path $Root '..\new\perip_bridge.sv')
)

foreach ($file in @($Tb, $IromCoe, $DramCoe) + $PeripheralFiles) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Required benchmark file is missing: $file"
    }
}

$Variants = if ($Version -eq 'both') { @('six', 'pipeline5') } else { @($Version) }
$Results = @()

foreach ($Variant in $Variants) {
    $RtlDir = if ($Variant -eq 'six') {
        Join-Path $Root 'sources_1\imports\rtl'
    } else {
        Join-Path $Root 'pipeline5'
    }
    $RunLabel = if ($Variant -eq 'six') {
        $Features = @()
        if ($SixStaticJal) { $Features += 'static_jal' }
        if ($SixMem2LoadFwd) { $Features += 'mem2_load_fwd' }
        if ($SixRas) { $Features += 'ras' }
        if ($Features.Count -eq 0) { 'six' } else { 'six_' + ($Features -join '_') }
    } else {
        $Variant
    }
    $WorkDir = Join-Path $BuildRoot $RunLabel
    $Snapshot = "demo_perf_${RunLabel}_sim"

    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

    $RtlFiles = @(Get-ChildItem -LiteralPath $RtlDir -Recurse -File -Filter '*.v' |
        Sort-Object FullName |
        ForEach-Object { $_.FullName })
    if ($RtlFiles.Count -eq 0) {
        throw "No RTL files found in $RtlDir"
    }

    $CompileArgs = @(
        '--sv',
        '-i', $RtlDir,
        '-i', (Join-Path $RtlDir 'alu'),
        '-i', (Join-Path $RtlDir 'pipe'),
        '-i', (Join-Path $RtlDir 'stage'),
        '-i', (Join-Path $RtlDir 'util')
    )
    if (($Variant -eq 'six') -and $SixStaticJal) {
        $CompileArgs += @('-d', 'SIX_STATIC_JAL_PRED')
    }
    if (($Variant -eq 'six') -and $SixMem2LoadFwd) {
        $CompileArgs += @('-d', 'SIX_MEM2_LOAD_FWD')
    }
    if (($Variant -eq 'six') -and $SixRas) {
        $CompileArgs += @('-d', 'SIX_RAS_PRED')
    }
    # The six-stage-only diagnostics reference its additional MEM2 interlock.
    # Keep the pipeline5 elaboration independent of those hierarchy names.
    if ($Variant -eq 'six') {
        $CompileArgs += @('-d', 'BENCH_SIX_STAGE')
    }
    if ($ToCompletion) {
        $CompileArgs += @('-d', 'BENCH_TO_COMPLETION')
    }
    if ($DumpVcd) {
        $CompileArgs += @('-d', 'BENCH_DUMP_VCD')
    }
    $CompileArgs += $RtlFiles + $PeripheralFiles + @($Tb)

    Push-Location $WorkDir
    try {
        Write-Host "`n=== Compile $Variant demo benchmark ==="
        & xvlog @CompileArgs
        if ($LASTEXITCODE -ne 0) {
            throw "xvlog failed for $Variant"
        }

        Write-Host "=== Elaborate $Variant demo benchmark ==="
        # Some legacy RTL source files omit `timescale.  Give those modules a
        # deterministic default instead of letting xelab reject a mixed-time
        # scale design in strict mode.
        & xelab 'KLDJ_demo_perf_tb' '-s' $Snapshot '--debug' 'typical' '--timescale' '1ns/1ps' '--relax'
        if ($LASTEXITCODE -ne 0) {
            throw "xelab failed for $Variant"
        }

        Write-Host "=== Run $Variant demo benchmark ==="
        # Vivado 2018.3 accepts -testplusarg from its generated TCL scripts
        # but not reliably from its Windows command-line front end.  The bench
        # has repository-root and build-directory COE fallbacks; the max-cycle
        # and VCD options above are compile-time macros for deterministic runs.
        $SimArgs = @($Snapshot, '--runall')
        $SimOutput = @(& xsim @SimArgs 2>&1)
        $SimExitCode = $LASTEXITCODE
        $LogPath = Join-Path $WorkDir "$RunLabel.demo_perf.log"
        $SimOutput | Tee-Object -FilePath $LogPath
        $OutputText = $SimOutput -join [Environment]::NewLine

        if (($SimExitCode -ne 0) -or ($OutputText -notmatch 'DEMO_PERF_PASS')) {
            throw "$Variant benchmark failed; see $LogPath"
        }

        $ResultLine = ($SimOutput | Where-Object { $_ -match 'DEMO_PERF_RESULT' } |
            Select-Object -Last 1)
        $Results += [PSCustomObject]@{
            Version = $RunLabel
            Result  = $ResultLine.ToString()
            Log     = $LogPath
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host "`n=== Demo benchmark summary ==="
$Results | Format-List
Write-Host 'Compare cycle counts first.  Convert to elapsed time only after using the actual timing-closed clock frequency for each build.'
if (-not $ToCompletion) {
    Write-Host 'Default mode stops at a common 100,000-retired-instruction window. Use -ToCompletion for the terminal-PC run.'
}
