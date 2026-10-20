[CmdletBinding()]
param([string] $IverilogDir = 'C:/iverilog/bin')
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectDir
try {
    & "$PSScriptRoot/run_take_sim.ps1" -IverilogDir $IverilogDir
    & "$PSScriptRoot/run_sim.ps1" -IverilogDir $IverilogDir -Tests @(
        'tb_take_atomic','tb_take_key_control','tb_take_spi_guard','tb_take_nor_store','tb_hc05_take',
        'tb_top_take','tb_hub75e_status','tb_hc05_extensions','tb_hc05_download',
        'tb_touch_tdm_synth','tb_gesture_external_control')
    & (Join-Path $IverilogDir 'iverilog.exe') -g2001 -s tb_tdm_take_equivalence -o sim/build/tb_tdm_take_equivalence.vvp `
        sim/tb_tdm_take_equivalence.v src/tdm_synth.v sim/reference/tdm_synth_before_take_opt.v src/sine_lookup.v
    if ($LASTEXITCODE -ne 0) { throw 'Audio equivalence compilation failed' }
    & (Join-Path $IverilogDir 'vvp.exe') sim/build/tb_tdm_take_equivalence.vvp | Tee-Object -FilePath sim/build/tb_tdm_take_equivalence.log
    if ($LASTEXITCODE -ne 0) { throw 'Audio equivalence failed' }
} finally { Pop-Location }
