[CmdletBinding()]
param(
    [string] $IverilogDir = 'C:/iverilog/bin',
    [string] $Python = 'python'
)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectDir
try {
    New-Item -ItemType Directory -Path 'sim/build' -Force | Out-Null
    $rtl = @('../pmod_hub75e/src/ttp229_gpio_input.v','src/twinkle_sequencer.v','src/sine_rom.v','src/dds_voice.v','src/adsr_env.v','src/envelope_gain.v','src/synth_voice.v','src/audio_mixer.v','src/poly_synth.v','src/gowin_fsr_adc.v','src/fsr_dynamics.v','src/fsr_mode_select.v','src/fsr_pitch_scaler.v','src/top.v','src/clk_div.v','src/i2s_tx.v','src/button_filter.v','sim/gowin_adc_model.v')
    & (Join-Path $IverilogDir 'iverilog.exe') '-g2001' '-Wall' '-s' 'tb_music_preview' '-o' 'sim/build/tb_music_preview.vvp' 'sim/tb_music_preview.v' @rtl
    if ($LASTEXITCODE -ne 0) { throw 'Music preview compile failed' }
    & (Join-Path $IverilogDir 'vvp.exe') '-i' 'sim/build/tb_music_preview.vvp' | Tee-Object -FilePath 'sim/build/music_preview_render.log'
    if ($LASTEXITCODE -ne 0) { throw 'Music preview render failed' }
    & $Python 'tools/pcm_to_wav.py' 'sim/build/music_preview_pcm.csv' 'sim/build/music_preview.wav' '--normalize'
    if ($LASTEXITCODE -ne 0) { throw 'Preview WAV export failed' }
} finally { Pop-Location }
