param(
    [string]$VivadoBin = 'D:\Xilinx_Vivado\Vivado\2023.2\bin',
    [string]$BuildDir = (Join-Path $env:TEMP ("kldj_mem_response_sim_{0}" -f $PID))
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rtl = Join-Path $projectRoot 'kldj.srcs2\sources_1\imports\rtl'
$new = Join-Path $projectRoot 'new'
$tb = Join-Path $projectRoot 'kldj.srcs2\sim_1\imports\sim\mem_response_pipeline_tb.sv'

$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'

foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Vivado simulation tool not found: $tool"
    }
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$rtlFiles = @()
$rtlFiles += Get-ChildItem -File (Join-Path $rtl '*.v')
$rtlFiles += Get-ChildItem -File (Join-Path $rtl 'alu\*.v')
$rtlFiles += Get-ChildItem -File (Join-Path $rtl 'pipe\*.v')
$rtlFiles += Get-ChildItem -File (Join-Path $rtl 'stage\*.v')
$rtlFiles += Get-ChildItem -File (Join-Path $rtl 'util\*.v')

$systemFiles = @(
    (Join-Path $new 'seg7.sv'),
    (Join-Path $new 'display_seg.sv'),
    (Join-Path $new 'counter.sv'),
    (Join-Path $new 'DRAM_TDP.sv'),
    (Join-Path $new 'dram_driver.sv'),
    (Join-Path $new 'perip_bridge.sv')
)

Push-Location $BuildDir
try {
    & $xvlog -sv `
        -i $rtl `
        -i (Join-Path $rtl 'alu') `
        -i (Join-Path $rtl 'pipe') `
        -i (Join-Path $rtl 'stage') `
        -i (Join-Path $rtl 'util') `
        $rtlFiles.FullName $systemFiles $tb
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed with exit code $LASTEXITCODE"
    }

    & $xelab mem_response_pipeline_tb `
        -s mem_response_pipeline_tb_sim `
        -debug typical
    if ($LASTEXITCODE -ne 0) {
        throw "xelab failed with exit code $LASTEXITCODE"
    }

    $consoleLog = Join-Path $BuildDir 'mem_response_console.log'
    & $xsim mem_response_pipeline_tb_sim -runall 2>&1 |
        Tee-Object -FilePath $consoleLog
    if ($LASTEXITCODE -ne 0) {
        throw "xsim failed with exit code $LASTEXITCODE"
    }

    if (-not (Select-String -LiteralPath $consoleLog `
            -SimpleMatch 'MEM RESPONSE PIPELINE TEST PASSED' -Quiet)) {
        throw "Simulation did not report PASS. See $consoleLog"
    }

    Write-Host "PASS: MEM-response pipeline simulation"
    Write-Host "Artifacts: $BuildDir"
}
finally {
    Pop-Location
}
