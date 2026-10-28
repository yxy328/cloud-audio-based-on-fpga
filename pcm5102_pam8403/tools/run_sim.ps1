[CmdletBinding()]
param(
    [string] $IverilogDir = 'C:/iverilog/bin',
    [string] $GowinDir = 'E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64',
    [string[]] $Tests,
    [string] $NetlistFile = 'impl/pnr/PCM5102_PAM8403.vo',
    [switch] $Netlist,
    [switch] $Quick,
    [switch] $FullNetlist
)
$ErrorActionPreference = 'Stop'
if ($FullNetlist -and (!$Netlist -or $Quick)) { throw '-FullNetlist requires -Netlist and cannot be combined with -Quick' }
# The production netlist uses live mode; its default pin-only test checks
# that physical song controls cannot trigger audio without touch events.
if ($Netlist -and !$FullNetlist) { $Quick = $true }
$projectDir = Split-Path -Parent $PSScriptRoot
$iverilog = Join-Path $IverilogDir 'iverilog.exe'
$vvp = Join-Path $IverilogDir 'vvp.exe'
foreach ($tool in @($iverilog, $vvp)) {
    if (!(Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing $tool" }
}
Push-Location -LiteralPath $projectDir
try {
    New-Item -ItemType Directory -Path 'sim/build' -Force | Out-Null
    if ($Netlist) {
        $rtl = @($NetlistFile, (Join-Path $GowinDir 'IDE/simlib/gw5a/prim_sim.v'))
        $defaultTests = @('tb_top_idle')
    } else {
        $rtl = @('../pmod_hub75e/src/ttp229_gpio_input.v','src/clk_div.v','src/i2s_tx.v','src/button_filter.v','src/twinkle_sequencer.v','src/sine_rom.v','src/dds_voice.v','src/adsr_config.v','src/adsr_env.v','src/envelope_gain.v','src/synth_voice.v','src/audio_mixer.v','src/poly_synth.v','src/gowin_fsr_adc.v','src/fsr_dynamics.v','src/fsr_mode_select.v','src/fsr_pitch_scaler.v','src/uart_8n1.v','src/hc05_command_decode.v','src/hc05_keymap.v','src/key_live_stream.v','src/downloadable_song.v','src/performance_logger.v','src/rhythm_guide.v','src/midi_note_lut.v','src/top.v','src/nco_sine.v','src/volume_key.v')
        $rtl += @('src/rhythm_game.v','src/hub75e_rhythm_display.v','src/hub75e_status.v','src/audio_visualizer.v','src/audio_scope.v','src/audio_spectrum.v','src/display_mode_control.v','src/lissajous_reference.v','src/audio_record_stream.v','src/performance_take.v','src/take_nor_store.v','src/take_spi_transaction.v','src/top_take.v','src/take_key_control.v','sim/take_nor_model.v')
        $rtl += @('src/ir_strings.v','sim/reference/sensor_staging_reference.v','src/sensor_poly_audio.v','src/tdm_synth.v','src/sine_lookup.v','src/synth_shared_arith.v')
        $rtlTests = @('tb_sensor_eight_timbres','tb_ttp229_tolerant','tb_ttp229_key1_key7','tb_ttp229_glitches','tb_hc05_extensions','tb_touch_tdm_synth','tb_top_touch16','tb_analog_expression','tb_touch_sine_rom','tb_audio_effects','tb_audio_master_volume','tb_audio_spectrum','tb_lissajous_delay','tb_lissajous_reference','tb_hc05_xy','tb_audio_visualizer','tb_audio_scope','tb_display_mode_control','tb_hub75e_audio_display','tb_top_audio_visual','tb_poly_pipeline','tb_midi_block_rom','tb_voice_bend','tb_hc05_bend','tb_top_voice_bend','tb_top_runtime_adsr','tb_runtime_adsr','tb_tdm_adsr','tb_hc05_adsr','tb_ir_strings','tb_tdm_queue','tb_sensor_poly_audio','tb_top_ir_tdm')
        $rtl += @('src/geita.v','src/gesture_top.v','src/gesture_audio.v','src/gesture_nco_sine.v','src/gesture_piano_voice.v','src/extra_voices.v','src/vibrato.v','src/apds9960_ctrl.v','src/i2c_master.v','src/ads1115_ctrl.v')
        $rtlTests += @('tb_top_score_config','tb_top_audition','tb_hc05_control_races','tb_top_integrated','tb_karplus','tb_karplus_external','tb_gesture_audio','tb_gesture_external_control','tb_gesture_nco_pipeline','tb_i2c_master_bus','tb_ads1115_bus','tb_apds_nack','tb_key_live_stream')
        $defaultTests = @('tb_top_live', 'tb_top_idle', 'tb_hub75e_rhythm_display', 'tb_rhythm_guide', 'tb_downloadable_song', 'tb_performance_logger', 'tb_hc05_download_fixed16', 'tb_uart_8n1', 'tb_hc05_keymap', 'tb_top_hc05_map', 'tb_gowin_fsr_adc', 'tb_fsr_adc_capture', 'tb_fsr_dynamics', 'tb_fsr_modes', 'tb_top_touch_response', 'tb_top_fsr_modes', 'tb_top_fsr', 'tb_fsr_pipeline', 'tb_ttp229_gpio_input', 'tb_top_touch', 'tb_twinkle_sequencer', 'tb_top_song', 'tb_dds_voice', 'tb_button_filter', 'tb_adsr_env', 'tb_envelope_gain', 'tb_audio_mixer', 'tb_poly_synth', 'tb_top', 'tb_audio_units')
    }
    if (!$Netlist) { $defaultTests += @('tb_top_dual_analog','tb_hub75e_status','tb_audio_record_stream','tb_hc05_audio_record','tb_top_audio_record') + $rtlTests }
    if (!$Netlist) { $rtl += @('sim/ttp229_model.v','src/touch_sine_rom.v','src/ttp229_keys.v','src/touch_tdm_synth.v','src/analog_expression.v','src/audio_effects.v','src/audio_master_volume.v') }
    $rtl += @('sim/i2s_pcm_monitor.v','src/audio_fx_chain.v')
    if (!$Netlist) { $rtl += @('src/audio_take_store.v','src/audio_nor_operation.v','src/top_audio_take.v','sim/audio_nor_model.v') }
    if (!$Netlist) { $rtl += @('sim/gowin_adc_model.v','sim/ads1115_model.v') }
    if (!$Netlist) { $defaultTests += @('tb_hc05_visual','tb_hc05_code39_equivalence','tb_song_time_bound','tb_top_hc05_only','tb_top_pedal','tb_touch_pedal_timing','tb_performance_params','tb_command_protocol','tb_vibrato_params','tb_tuning_params','tb_top_performance') }
    if (!$Netlist) { $rtl += @('sim/reference/hc05_keymap_parallel_reference.v','sim/reference/tdm_synth_parallel_reference.v','sim/reference/voice_pitch_scaler_reference.v','sim/reference/vibrato_fixed_reference.v','sim/reference/hub75e_rhythm_display_reference.v','sim/reference/sensor_poly_audio_reference.v') }
    if (!$Netlist) { $rtl += @('sim/reference/tdm_synth_fixed_reference.v') }
    if (!$Netlist) { $rtl += @('sim/reference/audio_effects_fixed_reference.v'); $defaultTests += @('tb_echo_params') }
    if (!$Netlist) {
        $rtl += @('sim/reference/tdm_synth_merge_reference.v','sim/reference/touch_tdm_synth_merge_reference.v')
        $defaultTests += @('tb_synth_shared_equivalence','tb_synth_shared_arith')
    }
    if(!$Netlist){$rtl += @('sim/reference/hc05_keymap_code39_reference.v','sim/reference/hc05_command_code39_reference.v','sim/reference/downloadable_song_code39_reference.v')}
    if(!$Netlist){$defaultTests+=@('tb_score256','tb_hc05_score256','tb_rhythm_game','tb_rhythm_panel','tb_rhythm_raster','tb_rhythm_protocol','tb_rhythm_top','tb_sensor_staging_equivalence')}
    $selectedTests = if ($Tests) { $Tests } else { $defaultTests }
    if ($Netlist -and ($selectedTests | Where-Object { $_ -in @('tb_top_hc05_map','tb_gowin_fsr_adc','tb_fsr_adc_capture','tb_fsr_modes','tb_top_touch_response','tb_top_fsr_modes','tb_top_fsr','tb_fsr_pipeline') })) {
        throw 'The Gowin ADC primitive library has no analog behavior model. These ADC tests use the RTL behavioral model; use -Netlist -Tests tb_top_idle for the production live-mode PNR smoke test.'
    }
    foreach ($test in $selectedTests) {
        $suffix = if ($Netlist) { '_netlist' } else { '' }
        if ($Quick) { $suffix += '_quick' }
        $output = "sim/build/$test$suffix.vvp"
        $defines = @()
        if ($Quick) { $defines = @('-D', 'AUDIO_QUICK_SIM') }
        $testFile = if ($test -eq 'tb_ttp229_gpio_input') { '../pmod_hub75e/sim/tb_ttp229_gpio_input.v' } else { "sim/$test.v" }
        & $iverilog '-g2001' '-Wall' @defines '-s' $test '-o' $output $testFile @rtl
        if ($LASTEXITCODE -ne 0) { throw "$test compile failed" }
        $pcmKind = if ($Netlist) { 'netlist' } else { 'rtl' }
        if ($Quick) { $pcmKind += '_quick' }
        $pcmFile = if ($test -eq 'tb_top_touch16') { 'sim/build/decoded_pcm_touch16.csv' } elseif ($test -eq 'tb_top_voice_bend') { 'sim/build/decoded_pcm_voice_bend.csv' } elseif ($test -eq 'tb_top_runtime_adsr') { 'sim/build/decoded_pcm_runtime_adsr.csv' } elseif ($test -eq 'tb_top_ir_tdm') { 'sim/build/decoded_pcm_top_ir_tdm.csv' } elseif ($test -eq 'tb_top_integrated') { 'sim/build/decoded_pcm_top_integrated.csv' } elseif ($test -eq 'tb_top_live') { 'sim/build/decoded_pcm_top_live.csv' } elseif ($test -eq 'tb_top_song') { 'sim/build/decoded_pcm_song_short.csv' } elseif ($test -eq 'tb_top_hc05_map') { "sim/build/decoded_pcm_hc05_map_$pcmKind.csv" } elseif ($test -eq 'tb_top_touch_response') { "sim/build/decoded_pcm_touch_response_$pcmKind.csv" } elseif ($test -eq 'tb_top_touch') { "sim/build/decoded_pcm_touch_$pcmKind.csv" } elseif ($test -eq 'tb_top_fsr_modes') { "sim/build/decoded_pcm_fsr_modes_$pcmKind.csv" } elseif ($test -eq 'tb_top_fsr') { "sim/build/decoded_pcm_fsr_$pcmKind.csv" } elseif ($test -eq 'tb_fsr_pipeline') { "sim/build/decoded_pcm_fsr_pipeline_$pcmKind.csv" } else { "sim/build/decoded_pcm_$pcmKind.csv" }
        if ($test -eq 'tb_top_pedal') { $pcmFile = "sim/build/decoded_pcm_pedal_$pcmKind.csv" }
        if ($test -eq 'tb_top_touch16_recovery') { $pcmFile = 'sim/build/decoded_pcm_touch16_recovery.csv' }
        & $vvp '-i' $output "+pcm_csv=$pcmFile" | Tee-Object -FilePath "sim/build/$test$suffix.log"
        if ($LASTEXITCODE -ne 0) { throw "$test simulation failed" }
    }
} finally { Pop-Location }
