[CmdletBinding()]
param([switch]$SkipApp)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
$tests=@(
    'tb_control12_touch_widths','tb_control12_touch_widths_fast',
    'tb_control12_touch_widths_loud','tb_control12_touch_widths_quiet',
    'tb_control12_pitch','tb_control12_dense','tb_control12_protocol',
    'tb_control12_take','tb_score_bend_slew','tb_score_bend_words',
    'tb_score_bend_manual_legacy','tb_hc05_code39_equivalence','tb_hc05_download_fixed16',
    'tb_key_live_stream','tb_control12_live_equivalence','tb_performance_take',
    'tb_take_atomic','tb_fx_take_atomic_528','tb_hc05_control_races',
    'tb_synth_shared_equivalence','tb_synth_shared_arith',
    'tb_control12','tb_control12_take_top'
)
& "$PSScriptRoot/run_sim.ps1" -Quick -Tests $tests
if(!$SkipApp){& "$projectDir/android_app/test-core.ps1"}
