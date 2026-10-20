param([string]$IverilogDir='C:/iverilog/bin')
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectDir
try {
    & python tools/generate_tdm_sine.py --check
    if($LASTEXITCODE -ne 0){throw 'Sine ROM check failed'}
    & "$PSScriptRoot/run_sim.ps1" -IverilogDir $IverilogDir -Tests tb_tdm_geometry_equivalence,tb_bend_ram_equivalence,tb_tdm_queue,tb_tdm_adsr,tb_sensor_eight_timbres,tb_sensor_poly_audio,tb_voice_bend
    $output='sim/build/tb_tdm_geometry_preset.vvp'
    & "$IverilogDir/iverilog.exe" -g2001 -s tb_tdm_geometry_equivalence '-Ptb_tdm_geometry_equivalence.PRESET=1' -o $output sim/tb_tdm_geometry_equivalence.v src/tdm_synth.v src/sine_lookup.v sim/reference/tdm_synth_parallel_reference.v
    if($LASTEXITCODE -ne 0){throw 'Preset-duration equivalence compilation failed'}
    & "$IverilogDir/vvp.exe" -i $output | Tee-Object -FilePath sim/build/tb_tdm_geometry_preset.log
    if($LASTEXITCODE -ne 0){throw 'Preset-duration equivalence failed'}
} finally { Pop-Location }
