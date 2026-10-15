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
# Primitive simulation is much slower; the bounded differential scenario is
# the default there. Default RTL also checks complete stop/release to silence.
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
        $defaultTests = @('tb_top')
    } else {
        $rtl = @('../pmod_hub75e/src/ttp229_gpio_input.v','src/clk_div.v','src/i2s_tx.v','src/button_filter.v','src/twinkle_sequencer.v','src/sine_rom.v','src/dds_voice.v','src/adsr_env.v','src/envelope_gain.v','src/synth_voice.v','src/audio_mixer.v','src/poly_synth.v','src/gowin_fsr_adc.v','src/fsr_dynamics.v','src/fsr_mode_select.v','src/fsr_pitch_scaler.v','src/uart_8n1.v','src/hc05_keymap.v','src/downloadable_song.v','src/performance_logger.v','src/pcm_clip_player.v','src/midi_note_lut.v','src/top.v','src/nco_sine.v','src/volume_key.v')
        $defaultTests = @('tb_pcm_clip_player', 'tb_downloadable_song', 'tb_performance_logger', 'tb_hc05_download', 'tb_uart_8n1', 'tb_hc05_keymap', 'tb_top_hc05_map', 'tb_gowin_fsr_adc', 'tb_fsr_adc_capture', 'tb_fsr_dynamics', 'tb_fsr_modes', 'tb_top_touch_response', 'tb_top_fsr_modes', 'tb_top_fsr', 'tb_fsr_pipeline', 'tb_ttp229_gpio_input', 'tb_top_touch', 'tb_twinkle_sequencer', 'tb_top_song', 'tb_dds_voice', 'tb_button_filter', 'tb_adsr_env', 'tb_envelope_gain', 'tb_audio_mixer', 'tb_poly_synth', 'tb_top', 'tb_audio_units')
    }
    $rtl += @('sim/i2s_pcm_monitor.v')
    if (!$Netlist) { $rtl += @('sim/gowin_adc_model.v') }
    $selectedTests = if ($Tests) { $Tests } else { $defaultTests }
    if ($Netlist -and ($selectedTests | Where-Object { $_ -in @('tb_top_hc05_map','tb_gowin_fsr_adc','tb_fsr_adc_capture','tb_fsr_modes','tb_top_touch_response','tb_top_fsr_modes','tb_top_fsr','tb_fsr_pipeline') })) {
        throw 'The Gowin ADC primitive library has no analog behavior model. These ADC tests use the RTL behavioral model; use -Netlist -Tests tb_top for audio-only PNR checks.'
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
        $pcmFile = if ($test -eq 'tb_top_song') { 'sim/build/decoded_pcm_song_short.csv' } elseif ($test -eq 'tb_top_hc05_map') { "sim/build/decoded_pcm_hc05_map_$pcmKind.csv" } elseif ($test -eq 'tb_top_touch_response') { "sim/build/decoded_pcm_touch_response_$pcmKind.csv" } elseif ($test -eq 'tb_top_touch') { "sim/build/decoded_pcm_touch_$pcmKind.csv" } elseif ($test -eq 'tb_top_fsr_modes') { "sim/build/decoded_pcm_fsr_modes_$pcmKind.csv" } elseif ($test -eq 'tb_top_fsr') { "sim/build/decoded_pcm_fsr_$pcmKind.csv" } elseif ($test -eq 'tb_fsr_pipeline') { "sim/build/decoded_pcm_fsr_pipeline_$pcmKind.csv" } else { "sim/build/decoded_pcm_$pcmKind.csv" }
        & $vvp '-i' $output "+pcm_csv=$pcmFile" | Tee-Object -FilePath "sim/build/$test$suffix.log"
        if ($LASTEXITCODE -ne 0) { throw "$test simulation failed" }
    }
} finally { Pop-Location }
