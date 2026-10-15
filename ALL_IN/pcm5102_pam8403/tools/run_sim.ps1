[CmdletBinding()]
param([string] $IverilogDir = '', [switch] $LongWave,
      [string[]] $Tests = @('tb_karplus', 'tb_guitar_top', 'tb_audio_units', 'tb_gesture_nco_pipeline', 'tb_gesture_audio', 'tb_top_sensors'))
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
if (!$IverilogDir) {
    $localBin = Join-Path $PSScriptRoot 'local_sim/icarus/app/bin'
    $IverilogDir = if (Test-Path (Join-Path $localBin 'iverilog.exe')) {
        $localBin
    } else { 'C:/iverilog/bin' }
}
$iverilog = Join-Path $IverilogDir 'iverilog.exe'
$vvp = Join-Path $IverilogDir 'vvp.exe'
foreach ($tool in @($iverilog, $vvp)) {
    if (!(Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Missing simulator: $tool; pass -IverilogDir <bin directory>."
    }
}
Push-Location -LiteralPath $projectDir
try {
    New-Item -ItemType Directory -Path 'sim/build' -Force | Out-Null
    $rtl = @(Get-ChildItem src/*.v | ForEach-Object FullName) +
           @('sim/gowin_adc_model.v', 'sim/i2s_pcm_monitor.v')
    foreach ($test in $Tests) {
        if ($test -notmatch '^tb_[A-Za-z0-9_]+$' -or
            !(Test-Path -LiteralPath "sim/$test.v")) { throw "Unknown test: $test" }
        $output = "sim/build/$test.vvp"
        & $iverilog '-g2001' '-Wall' '-s' $test '-o' $output "sim/$test.v" @rtl
        if ($LASTEXITCODE -ne 0) { throw "$test compile failed." }
        if ($LongWave -and $test -eq 'tb_guitar_top') {
            & $vvp $output '+long_wave'
        } else {
            & $vvp $output
        }
        if ($LASTEXITCODE -ne 0) { throw "$test simulation failed." }
    }
    Write-Host 'PASS: PCM5102 + PAM8403 audio simulations completed.'
}
finally { Pop-Location }


