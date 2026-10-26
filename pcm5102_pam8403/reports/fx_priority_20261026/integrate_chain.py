from pathlib import Path
import subprocess,sys
HERE=Path(__file__).resolve().parent
P=HERE/'chain/pcm5102_pam8403'
def replace(s,a,b):
    assert s.count(a)==1,repr(a)
    return s.replace(a,b)
key=P/'src/hc05_keymap.v';s=key.read_text(encoding='utf-8-sig')
s=replace(s,'output reg [1:0] echo_tap,','output wire [1:0] echo_tap,')
s=replace(s,'    output reg [1:0] effect_mode,\n    output reg [3:0] effect_wet,',
'''    output wire [1:0] effect_mode,
    output wire [3:0] effect_wet,
    output reg [2:0] fx_mask,
    output reg [7:0] fx_settings,
    output reg [11:0] fx_mix,
    input wire [2:0] fx_applied_mask,
    input wire [7:0] fx_applied_settings,
    input wire [11:0] fx_applied_mix,''')
s=replace(s,"    assign touch_mode16=1'b1;",'''    assign touch_mode16=1'b1;
    assign echo_tap=fx_settings[3:2];
    assign effect_mode=fx_mask[1] ? 2'd1 : fx_mask[0] ? 2'd2 : 2'd0;
    assign effect_wet=fx_mask[1] ? fx_mix[7:4] : fx_mask[0] ? fx_mix[3:0] :
        fx_mask[2] ? fx_mix[11:8] : fx_mix[3:0];''')
s=replace(s,'panic<=0;effect_mode<=0;effect_wet<=4;',"panic<=0;fx_mask<=0;fx_settings<=8'h52;fx_mix<=12'h444;")
s=replace(s,'echo_tap<=0;','')
s=replace(s,'echo_tap<=pitch0[1:0];','fx_settings[3:2]<=pitch0[1:0];')
s=replace(s,'                            control_parse<=2;parse_numbers(7,2);',
'''                            if(line_length==8 && line[7:0]=="?")begin
                                reply<={1'b0,fx_mask,fx_settings,fx_mix,1'b0,fx_applied_mask,fx_applied_settings,fx_applied_mix,64'd0};
                                respond(5'd30,6'd27);
                            end else begin control_parse<=2;parse_numbers(7,2);end''')
s=replace(s,'''                                    2:if(value0>2 || accumulator>8)result(2);
                                      else begin effect_mode<=value0[1:0];effect_wet<=accumulator[3:0];result(0);end''',
'''                                    2:if(field_count==4)begin
                                          if(value0!=3 || value1>7 || value2>255 || accumulator>4095 ||
                                             accumulator[3:0]>8 || accumulator[7:4]>8 || accumulator[11:8]>8)result(2);
                                          else begin fx_mask<=value1[2:0];fx_settings<=value2[7:0];fx_mix<=accumulator[11:0];result(0);end
                                      end else if(value0>2 || accumulator>8)result(2);
                                      else begin
                                          fx_mask<=value0==1 ? 3'd2 : value0==2 ? 3'd1 : 3'd0;
                                          fx_mix<={accumulator[3:0],accumulator[3:0],accumulator[3:0]};
                                          if(value0==1)fx_settings[5:4]<=1;
                                          if(value0==2)fx_settings[1:0]<=3;
                                          result(0);
                                      end''')
s=replace(s,'''                                if(have_digit)begin
                                    if(field_index==0) value0<=accumulator;''',
'''                                if(control_parse==2 && field_index==0 && accumulator==3)field_count<=4;
                                if(have_digit)begin
                                    if(field_index==0) value0<=accumulator;''')
key.write_text(s,encoding='utf-8')
gen=P/'tools/generate_hc05_replies.py';s=gen.read_text(encoding='utf-8-sig')
template='EFFECT3,#,##,###,#,##,###\r\n'
assert len(template)==27,len(template)
s=replace(s,"    'EFFECT2,#\\r\\n',","    'EFFECT2,#\\r\\n',\n    'EFFECT3,#,##,###,#,##,###\\r\\n',")
gen.write_text(s,encoding='utf-8')
subprocess.run([sys.executable,str(gen)],check=True)
subprocess.run([sys.executable,str(P/'tools/generate_hc05_decoder.py'),'--check'],check=True)
top=P/'src/top.v';s=top.read_text(encoding='utf-8-sig')
s=replace(s,'    wire [3:0] effect_wet;',
'''    wire [3:0] effect_wet;
    wire [2:0] fx_mask,fx_applied_mask;
    wire [7:0] fx_settings,fx_applied_settings;
    wire [11:0] fx_mix,fx_live_mix,fx_applied_mix;''')
s=replace(s,'        .effect_mode(effect_mode),.effect_wet(effect_wet),.master_volume(master_volume),',
'''        .effect_mode(effect_mode),.effect_wet(effect_wet),.master_volume(master_volume),
        .fx_mask(fx_mask),.fx_settings(fx_settings),.fx_mix(fx_mix),
        .fx_applied_mask(fx_applied_mask),.fx_applied_settings(fx_applied_settings),.fx_applied_mix(fx_applied_mix),''')
s=replace(s,'''    assign perf_live_state={live_note_gates,{11'd0,gesture_bank,gesture_vibrato,gesture_timbre},
        {10'd0,effect_mode,effective_wet},{3'd0,master_target},effective_pitch_ratio,fsr_gain,
        {14'd0,sensor_adsr},touch_adsr,touch_phase_increments[223:0]};''',
'''    // Version1 uses formerly reserved bits; all existing musical fields stay put.
    assign perf_live_state={live_note_gates,{1'b1,10'd0,gesture_bank,gesture_vibrato,gesture_timbre},
        {1'b0,fx_settings,fx_mask,effective_wet},{3'd0,master_target},effective_pitch_ratio,fsr_gain,
        {fx_live_mix,2'd0,sensor_adsr},touch_adsr,touch_phase_increments[223:0]};''')
start=s.index('    // Dry bypass retains the original frame timing.')
end=s.index('    audio_master_volume u_master_volume (',start)
s=s[:start]+'''    // ANALOG4 overrides effective wet levels, preserving each configured value.
    assign fx_live_mix=(analog_mode==4 && analog_available) ?
        {effective_wet,effective_wet,effective_wet} : fx_mix;
    wire [1:0] old_replay_mode=perf_state[485:484];
    assign fx_applied_mask=perf_replay ? (perf_state[511] ? perf_state[486:484] :
        old_replay_mode==1 ? 3'd2 : old_replay_mode==2 ? 3'd1 : 3'd0) : fx_mask;
    assign fx_applied_settings=perf_replay ? (perf_state[511] ? perf_state[494:487] :
        {2'd1,2'd1,echo_tap,2'd3}) : fx_settings;
    assign fx_applied_mix=perf_replay ? (perf_state[511] ? perf_state[431:420] :
        {perf_state[483:480],perf_state[483:480],perf_state[483:480]}) : fx_live_mix;
    audio_fx_chain u_effects (
        .clk(clk),.resetn(resetn && !panic && !perf_kill),.sample_valid(frame_ce),.dry(dry_audio_sample),
        .mask(fx_applied_mask),.settings(fx_applied_settings),.wet_mix(fx_applied_mix),
        .sample(effect_sample),.valid(effect_valid),.overrun());
'''+s[end:]
s=replace(s,'(perf_replay ? perf_state[484 +: 2] : effect_mode)==0 ? dry_audio_sample : effect_sample',
    'fx_applied_mask==0 ? dry_audio_sample : effect_sample')
top.write_text(s,encoding='utf-8')
g=P/'PCM5102_UNIFIED.gprj';s=g.read_text(encoding='utf-8-sig')
s=replace(s,'</FileList>','<File path="src/audio_fx_chain.v" type="file.verilog" enable="1"/></FileList>');g.write_text(s,encoding='utf-8')
runner=P/'tools/run_sim.ps1';s=runner.read_text(encoding='utf-8-sig')
s=replace(s,"$rtl += @('sim/i2s_pcm_monitor.v')","$rtl += @('sim/i2s_pcm_monitor.v','src/audio_fx_chain.v')")
runner.write_text(s,encoding='utf-8-sig')
print('Integrated real protocol/state/TAKE mux and independent chain in isolated candidate')
