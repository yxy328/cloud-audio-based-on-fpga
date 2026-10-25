# Regression status (logs newer than 2026-10-24 17:23)

Collected 2026-10-24 17:51; 75 logs.

| log | status | verdict line |
|---|---|---|
| `tb_adsr_env.log` | PASS | PASS [ADSR]: 106459 exact linear samples; A=98 D=3906 S=39321 R=24414; mid-stage release, continuous retrigger, divider cancellation, low-level release, CE hold, zero/one durations, extreme sustain, r |
| `tb_analog_expression.log` | PASS | PASS analog expression: FSR passthrough, volume cap/endpoints, pitch, all wet codes, full vibrato period, timeout/stale fallback |
| `tb_apds_nack.log` | PASS | PASS: absent APDS retries initialization, records NACK and emits no false gesture |
| `tb_audio_effects.log` | PASS | PASS FX independent circular-buffer model: 59005 samples, exact dry/wet, echo feedback tails, chorus tap modulation, mode clears, signed saturation (13356 clipped) |
| `tb_audio_master_volume.log` | PASS | PASS master volume signed PCM, exact mute/unity, bounded monotonic slew, frame-only updates, reversal and reset |
| `tb_audio_mixer.log` | PASS | PASS [mixer]: 1011 vectors; full-scale four-way sum, positive/negative clipping, cancellation, 1/4 scaling, 1000 random vectors, CE hold and reset |
| `tb_audio_record_stream.log` | PASS | PASS audio record stream: exact live PCM, real 2Mbps UART, CTS slots, CRC/seq/session/index, partial tail, overflow abort and clean restart |
| `tb_audio_scope.log` | PASS | PASS scope hue33: 65536 signed magnitudes, 2016 coordinates, 387 range selections, 64 monotonic saturated palette codes, +/-1 cyan/zero gray, 33 rising/falling window snapshots, no stale peak, six RTL |
| `tb_audio_spectrum.log` | PASS | PASS audio spectrum: silence, single/two tones, CIC alias rejection, full complex FFT dump |
| `tb_audio_units.log` | PASS | PASS [units]: all 256 sine values and phase wrap, two-stage key sync, signed half/quarter gain, 7 adversarial stereo TX frames |
| `tb_audio_visualizer.log` | PASS | PASS audio visualizer: 65536 signed PCM coordinates, 48-bin whole-window extrema/buffering, signed peaks/decay, delayed-audio XY bitmap, real FFT bars/gaps/noise floor and pixel colors |
| `tb_button_filter.log` | PASS | PASS [buttons]: short bounce ignored, one event per hold, release/repress accepted |
| `tb_command_protocol.log` | PASS | PASS performance protocol: 81 wire-level replies, sparse fields, atomic rejection, busy guards, 64/65-byte frames |
| `tb_dds_voice.log` | PASS | PASS [DDS]: 1024 ROM addresses, 8203 runtime phase/enable checks, continuous phase on pitch changes |
| `tb_display_mode_control.log` | PASS | PASS display mode: short release, threshold, one action/hold, long release suppression, guide/wave/XY/spectrum cycle, reset |
| `tb_downloadable_song.log` | PASS | PASS tb_downloadable_song: atomic banks, chords/rests, shared RAM, timing, lookahead, backpressure, STOP/restart, 128 dense notes |
| `tb_echo_params.log` | PASS | PASS effects runtime: 70000 default frames clock-exact; four impulse delays; 6:1 exact full-scale signed low-pass filtering; full-rate dry; fixed chorus/default phase wrap |
| `tb_envelope_gain.log` | PASS | PASS [gain]: 1010 signed products; unsigned full-scale gain, negative extrema, zero/half/full gain, 1000 random pairs, CE hold, reset |
| `tb_fsr_adc_capture.log` | PASS | PASS [ADC capture]: stale-ready rejection, asynchronous ready and stable bus, single completion, timeout/sample hold, retry recovery, reset |
| `tb_fsr_dynamics.log` | PASS | PASS [FSR dynamics]: all 1024 codes in both gain directions, heavy force lowers volume, <=1 gain-LSB error, independent AO polarity, zero floor, 64-LSB slew, CE hold and reset |
| `tb_fsr_modes.log` | PASS | PASS [FSR modes]: startup-held/bounce/long-press key 8, default volume, both calibrated 1024-code mappings, neutral inactive control, switch without fresh ADC, 64-LSB slew/CE/reset; all 32768 ratios f |
| `tb_fsr_pipeline.log` | PASS | PASS [production FSR pipeline]: three on-chip ADC modeled conversions, force lowers gain, release restores full, bounded 64-LSB steps, idle I2S; 185 stereo pairs |
| `tb_gesture_audio.log` | PASS | PASS: eight gesture mappings, ready/direction guards, retrigger, latched pitch, S2 timbre/vibrato, final silence |
| `tb_gesture_external_control.log` | PASS | PASS: external gesture control, unchanged default PCM, ignored buttons, latched bank/timbre, five voices, vibrato and final silence |
| `tb_gesture_nco_pipeline.log` | PASS | PASS: registered gesture sine matches 1024 original audio-rate samples including phase wrap |
| `tb_gowin_fsr_adc.log` | PASS | PASS [on-chip ADC]: 2.5MHz clock, 1kHz requests, 1.28us request hold, 1024-cycle conversion model, five raw/normalized boundary codes, valid pulse |
| `tb_hc05_adsr.log` | PASS | PASS UART ADSR: 20 replies; profile conversion, strict four fields, bounds/zero, invalid-command atomicity, controls while notes/score busy, independent restore |
| `tb_hc05_audio_record.log` | PASS | PASS audio control: 21 real UART transactions, strict session/range, busy/CTS/status, pulse counts, 16-key/hold/analog coexistence, legacy event log guards, no PCM command |
| `tb_hc05_bend.log` | PASS | PASS UART bend: 19 replies, endpoints, exact voice address, strict fields/bounds/atomic rejection, busy playing allowed, reset, ADSR coexistence |
| `tb_hc05_control_races.log` | PASS | PASS tb_hc05_control_races: real UART map lock during hardware validation, stale completion rejection, ordinary immediate/delayed ACKs |
| `tb_hc05_decoder_equivalence.log` | PASS | PASS HC05 decoder differential: 512 UART transactions, exact replies/control values/pulses, mutated commands and random lines |
| `tb_hc05_download.log` | PASS | PASS [HC05 downloads]: UART score atomicity/retry/map validation, sample commands rejected, recording framing/map lock/initial/final states |
| `tb_hc05_extensions.log` | PASS | PASS extension UART: 40 bit-level replies, state/ADC query, busy/recording gates, strict bounds/atomic rejection, panic |
| `tb_hc05_keymap.log` | PASS | PASS [HC05 protocol]: 57 replies; all commands/keys/13 notes, exact DDS steps/pressure octave, busy guards, query bursts, CR/LF/CRLF, invalid/partial/long/binary lines, framing recovery and reset |
| `tb_hc05_visual.log` | PASS | PASS visual UART: four pages, requested/active state, 32-byte atomic snapshots, strict errors, XY/PING coexistence |
| `tb_hc05_xy.log` | PASS | PASS UART XY: all 16 settings, strict syntax/range, atomic rejection, one write/command, available while playing, PING coexistence |
| `tb_hub75e_audio_display.log` | PASS | PASS HUB audio display: external wave/XY pixels, FFT startup blanking, RAM prefetch, three group bars, unchanged 133-clock scan, whole-PWM four-mode switch, hidden guide descent |
| `tb_hub75e_rhythm_display.log` | PASS | PASS hub75e_rhythm_display: external RGB5/133-clock scan, descent/bursts/scroll/STOP, 3002 arithmetic cases, 6174 reference row pairs |
| `tb_hub75e_status.log` | PASS | PASS HUB status: 32-plane external RGB reconstruction, 8/16 keys, hold, IR, fonts, exact bars, ADC alarm, whole-frame snapshots, guide transition, 133-clock scan |
| `tb_i2c_master_bus.log` | PASS | PASS: pin-level I2C write ACK, repeated-start two-byte read, master ACK/NACK, absent-slave NACK and bus release |
| `tb_ir_strings.log` | PASS | PASS IR startup/filter/rearm, all 256 simultaneous subsets, overlapping dispatch, held blockage and reset cancellation |
| `tb_karplus.log` | PASS | PASS: noise, 40000 reference samples, release tail, retrigger |
| `tb_karplus_external.log` | PASS | PASS: external guitar ignores S1, captures one-clock/inter-frame/frame/feedback triggers and sustains |
| `tb_key_live_stream.log` | PASS | PASS key_live_stream: 9 lines, framing and queueing verified |
| `tb_lissajous_delay.log` | PASS | PASS Lissajous: exact 32-sample delayed Y, signed step trajectory, zero signal center and cleared next frame |
| `tb_lissajous_reference.log` | PASS | PASS reference XY: 12 ratio/phase combinations, 3072 sine points, max error 0.494860 pixels, atomic capture/publish, eight crossing, circle geometry/clear and REF label |
| `tb_midi_block_rom.log` | PASS | PASS MIDI block ROM: 256 notes on each of seven addresses, exact reference mapping/invalid zero, synchronous read |
| `tb_performance_logger.log` | PASS | PASS tb_performance_logger: MAP, events, FIFO64, overflow, STOP, 33-byte EVT, uint32 limits, stalls |
| `tb_performance_params.log` | PASS | PASS performance parameters: every-clock frozen default comparison, fractional 5/60/200/500ms glide, new bounds |
| `tb_poly_pipeline.log` | PASS | PASS [polyphony]: 4825 mathematical sample/mix frames; 12315 unchanged-voice comparisons; four sustain voices, isolated pitch change/release, continuous retrigger, all four gate mappings, final silenc |
| `tb_poly_synth.log` | PASS | PASS [polyphony]: 4825 mathematical sample/mix frames; 12315 unchanged-voice comparisons; four sustain voices, isolated pitch change/release, continuous retrigger, all four gate mappings, final silenc |
| `tb_rhythm_guide.log` | PASS | PASS rhythm_guide: seven lanes, exact 1500ms fall, late/early lookahead, chords, touch, overflow, stop |
| `tb_runtime_adsr.log` | PASS | PASS runtime ADSR: all 1001 ms values, sustain mapping, profile reset/conversion, exact touch A/D/S/R, held snapshot/new note, mid-attack release |
| `tb_sensor_eight_timbres.log` | PASS | PASS eight sensor timbres: IR event path, eight distinct nonzero PCM waveforms, independent allocation, release silence, frame deadline |
| `tb_sensor_poly_audio.log` | PASS | PASS sensor producer queue: IR audio without APDS, blocked gestures while not ready, same-clock events, latched tone, backpressure/capacity/overflow/reset |
| `tb_song_time_bound.log` | PASS | PASS song bound: 128 x 60000ms, 23-bit horizon, note-off boundaries, stalled visual drain without wrap |
| `tb_synth_shared_arith.log` | PASS | PASS shared arithmetic arbitration: sensor priority, look_aux2 retention, signed and 51-bit products, rom phase mux, wait 2/6, 17 rom comparisons |
| `tb_synth_shared_equivalence.log` | PASS | PASS shared arithmetic exact equivalence: joint_frames=1668 sensor_frames=1671 touch_frames=1671 sensor_max=951 touch_max=842 mul_stalls=13756 rom_stalls=40569 max_wait=1/6 tuning_hold_hits=39808 timb |
| `tb_tdm_adsr.log` | PASS | PASS TDM ADSR: exact A4/D4/S128/R8, event snapshot, timed note-off, silence, TEST32 bypass, 32 voices max 951 clocks |
| `tb_tdm_queue.log` | PASS | PASS TDM FIFO64, 32-command budget, oldest replacement, frame snapshot, 32-note signed saturation, overflow/reset/deadline diagnostics; max 951 clocks |
| `tb_top_hc05_map.log` | PASS | PASS [top HC05, real I2S/accelerated UART]: key 1 G4=1228.54, reset C4=1226.07, upper C5=1228.13, pressure octave C4=1225.76; busy protection for held/raw notes/song, PING while playing, DDS phase con |
| `tb_top_idle.log` | PASS | PASS [live idle]: production parameters; S1/S2 produce no audio without touch, 136 stereo pairs |
| `tb_top_touch_response.log` | PASS | PASS [note 7 response]: OUT-to-first-PCM=1.802231ms, OUT-to-verified-silence=12.032312ms |
| `tb_touch_pedal_timing.log` | PASS | PASS default 1200ms pedal: exactly 58594 samples, four linked segments, continuous phase, silence, no overrun/clipping |
| `tb_touch_sine_rom.log` | PASS | PASS shared sine ROM: exact original waveform on all 1024 addresses, four independent phases |
| `tb_touch_tdm_synth.log` | PASS | PASS touch TDM: 16 chromatic/pedal phase increments x32 frames (zero error), 4096-sample spectrum G4..F5, independent ADSR/profile snapshots/releases, smooth shared pitch, deadline |
| `tb_ttp229_glitches.log` | PASS | PASS TTP229 window voting: 32 short-disturbed frames corrected, 16 long/ambiguous frames rejected, no false note/release, recovery and 16-key chord |
| `tb_ttp229_gpio_input.log` | PASS | PASS: extracted GPIO reader, all OUT1..8 positions, both polarities, 20ms independent debounce, bounce, disable/rearm, 20us frames and 600ms startup |
| `tb_ttp229_key1_key7.log` | PASS | PASS user key1/key7 case: four disturbed frames corrected to RAW=0001 DOWN=0001, genuine 1+7 chord and separate release/re-press preserved |
| `tb_ttp229_tolerant.log` | PASS | PASS short-noise tolerance: continuous paired endpoint pulses, responsive press/release/rearm, genuine 1+7 and 16-key chords, no bad-frame starvation |
| `tb_tuning_params.log` | PASS | PASS tuning scope: 32 sensor voices retuned, all 16 touch voices fixed, -12/A415, +3/A442, +12/A466, <=1 DDS tick error; sensor max busy 888 clocks, 1376 increments |
| `tb_twinkle_sequencer.log` | PASS | PASS [twinkle sequencer]: 42 exact score events; production beat/gap/intro/tail counts; six double beats; one-shot end, stop, idle/active restart, simultaneous event priority and reset |
| `tb_uart_8n1.log` | PASS | PASS [UART 8N1 at 50MHz/9600]: 256 bytes/back-to-back, +/-2% baud, false start, FIFO overflow/flush/EOL recovery, framing error/suffix discard, independent TX decode |
| `tb_vibrato_params.log` | PASS | PASS vibrato parameters: every-clock frozen defaults, 8Hz/depth1023 without intermediate wrap, 9766-frame global onset; pitch bounds 43151927..48899362 |
| `tb_voice_bend.log` | PASS | PASS per-voice bend: exact unity/bounds, 1024 monotonic steps, independent seven keys, FSR stacking, invalid guards, smooth reset, audio-frame timing |

Counts: PASS=75
