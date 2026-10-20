[CmdletBinding()]
param([string] $IverilogDir = 'C:/iverilog/bin')
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectDir
try {
    & "$PSScriptRoot/run_sim.ps1" -IverilogDir $IverilogDir -Tests @(
        'tb_audio_take_safety','tb_top_flash_audio','tb_top_hc05_only',
        'tb_hc05_audio_record','tb_take_spi_guard','tb_touch_tdm_synth')
    & "$projectDir/android_app/test-core.ps1"
} finally { Pop-Location }
