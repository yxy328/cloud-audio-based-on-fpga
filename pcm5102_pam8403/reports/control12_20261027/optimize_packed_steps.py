from pathlib import Path
R=Path(__file__).resolve().parent;P=R/'candidate/pcm5102_pam8403'
# Replace the first two-port prototype with paired context words, using
# the device's 32-bit simple-dual-port mode in the same single block.
p=P/'src/touch_tdm_synth.v'
s=(P/'sim/build/unified/control12_shared_reply/pcm5102_pam8403/src/touch_tdm_synth.v').read_text(encoding='utf-8')
def sub(a,b):
    global s
    assert a in s,a[:100]
    s=s.replace(a,b)
sub('parameter integer SHARED_ARITH=0, FAST_READ=0,','parameter integer SHARED_ARITH=0, FAST_READ=0, RAM_STEPS=0,')
sub('input wire legacy_high_keys,','input wire legacy_high_keys,\n    input wire [CONTROL_KEYS*32-1:0] replay_steps,\n    input wire replay_select,')
sub('''// one 256x16 context RAM. Worst-case 16 simultaneous segment divisions
// complete within the 1024-clock stereo frame. First seven retain remap/bend.''','''// one context RAM. RAM_STEPS pairs its 16-bit context fields into 32-bit
// words and stores a coherent frame's scaled pitches in the same block.
// Sixteen simultaneous segment divisions fit the 1024-clock stereo frame.''')
sub('''    // Thirteen 16-bit words per voice fit one 18Kbit synchronous RAM.
    // Serial context reads/writes avoid a wide shallow RAM and LUT mux bank.
    (* syn_ramstyle="block_ram" *) reg [15:0] contexts[0:255];
    reg [15:0] context_q;''','''    // Legacy layout: one 16-bit field/word, context 0..14, stride 16.
    // Packed layout: pairs of fields in words 0..7, pitch in word 8.
    // 256x32 fits one simple-dual-port 18K block, like the legacy 256x16.
    localparam CW=RAM_STEPS ? 32 : 16;
    (* syn_ramstyle="block_ram" *) reg [CW-1:0] contexts[0:255];
    reg [CW-1:0] context_q;''')
sub('WAVE_WAIT=14;','WAVE_WAIT=14,SNAPSHOT=15;')
sub('reg frame_legacy;','''reg frame_legacy,frame_replay;
    reg [31:0] voice_step;
    wire controlled=index<7 || (CONTROL_KEYS>7 && !frame_legacy && index<CONTROL_KEYS);''')
sub('''    always @(posedge clk)begin
        if(resetn && (state==INIT || state==STORE || state==GAIN || state==GAIN_WAIT))
            contexts[state==INIT ? init_address : {index,field}]<=state==INIT ? 16'd0 : context_write;
    end''','''    reg [31:0] packed_write;
    always @*begin
        case(field)
            0:packed_write=phase;
            1:packed_write={gain,9'd0,tail_part,seen_physical,seen,stage};
            2:packed_write={ticks,target};3:packed_write={step,length};
            4:packed_write={error,remainder};5:packed_write={sustain,decay};
            6:packed_write={age[15:0],release_time};default:packed_write={16'd0,age[31:16]};
        endcase
    end
    wire [31:0] live_step=low_steps[index*32 +: 32];
    wire [31:0] replay_step=replay_steps[index*32 +: 32];
    wire [31:0] capture_step=frame_replay ? replay_step : live_step;
    generate if(RAM_STEPS)begin: packed_context_port
        always @(posedge clk)
            if(resetn && (state==INIT || state==SNAPSHOT || state==STORE))
                contexts[state==INIT ? init_address : {index,state==SNAPSHOT ? 4'd8 : field}]<=
                    state==INIT ? 32'd0 : state==SNAPSHOT ? capture_step : packed_write;
    end else begin: old_context_port
        always @(posedge clk)
            if(resetn && (state==INIT || state==STORE || state==GAIN || state==GAIN_WAIT))
                contexts[state==INIT ? init_address : {index,field}]<=state==INIT ? 16'd0 : context_write;
    end endgenerate''')
sub('frame_gates<=0;frame_steps<=0;config_snapshot<=0;ratio_snapshot<=65535;','frame_gates<=0;frame_steps<=0;frame_legacy<=0;frame_replay<=0;voice_step<=0;config_snapshot<=0;ratio_snapshot<=65535;')
sub('frame_gates<=gates;frame_steps<=low_steps;frame_legacy<=legacy_high_keys;config_snapshot<=adsr_config;ratio_snapshot<=pitch_ratio;','frame_gates<=gates;if(!RAM_STEPS)frame_steps<=low_steps;frame_legacy<=legacy_high_keys;frame_replay<=replay_select;config_snapshot<=adsr_config;ratio_snapshot<=pitch_ratio;')
sub('''                    index<=0;sum<=0;state<=LOAD;
                end
                LOAD:''','''                    index<=0;sum<=0;state<=RAM_STEPS ? SNAPSHOT : LOAD;
                end
                SNAPSHOT:begin
                    if(index==(frame_legacy ? 7 : CONTROL_KEYS)-1)begin index<=0;state<=LOAD;end
                    else index<=index+1'b1;
                end
                LOAD:''')
sub('''                    case(field)
                        0:phase[15:0]<=context_q;1:phase[31:16]<=context_q;
                        2:{tail_part,seen_physical,seen,stage}<=context_q[6:0];3:gain<=context_q;4:target<=context_q;
                        5:ticks<=context_q;6:length<=context_q;7:step<=context_q;
                        8:remainder<=context_q;9:error<=context_q;10:decay<=context_q;
                        11:sustain<=context_q;12:release_time<=context_q;
                    endcase
                    if(field==12)begin address<={index,4'd13};state<=ENV;end''','''                    if(RAM_STEPS)begin
                        case(field)
                            0:phase<=context_q;
                            1:begin {tail_part,seen_physical,seen,stage}<=context_q[6:0];gain<=context_q[31:16];end
                            2:begin target<=context_q[15:0];ticks<=context_q[31:16];end
                            3:begin length<=context_q[15:0];step<=context_q[31:16];end
                            4:begin remainder<=context_q[15:0];error<=context_q[31:16];end
                            5:begin decay<=context_q[15:0];sustain<=context_q[31:16];end
                            6:begin release_time<=context_q[15:0];age[15:0]<=context_q[31:16];end
                            7:age[31:16]<=context_q[15:0];
                            8:voice_step<=context_q;
                        endcase
                    end else begin
                        case(field)
                            0:phase[15:0]<=context_q;1:phase[31:16]<=context_q;
                            2:{tail_part,seen_physical,seen,stage}<=context_q[6:0];3:gain<=context_q;4:target<=context_q;
                            5:ticks<=context_q;6:length<=context_q;7:step<=context_q;
                            8:remainder<=context_q;9:error<=context_q;10:decay<=context_q;
                            11:sustain<=context_q;12:release_time<=context_q;
                        endcase
                    end
                    if(field==(RAM_STEPS ? 8 : 12))begin address<={index,4'd13};state<=ENV;end''')
sub('seen<=frame_gates[index];state<=PITCH;','seen<=frame_gates[index];state<=RAM_STEPS && controlled ? WAVE : PITCH;')
sub("seen_physical<=frame_physical[index];address<={index,4'd14};age_load<=2;","seen_physical<=frame_physical[index];address<={index,4'd14};if(!RAM_STEPS)age_load<=2;")
sub('remainder<=rem_next[15:0];state<=PITCH;','remainder<=rem_next[15:0];state<=RAM_STEPS && controlled ? WAVE : PITCH;')
sub('phase<=phase+((index<7 || (CONTROL_KEYS>7 && !frame_legacy && index<CONTROL_KEYS)) ? frame_steps[index*32+:32] :','phase<=phase+(controlled ? (RAM_STEPS ? voice_step : frame_steps[index*32+:32]) :')
sub('if(field==12)begin\n                        if(index==15)', 'if(field==(RAM_STEPS ? 7 : 12))begin\n                        if(index==15)')
sub('''        assign gains[debug_voice*16+:16]=contexts[debug_voice*16+3];
        assign states[debug_voice*3+:3]=contexts[debug_voice*16+2][2:0];
        assign phases[debug_voice*32+:32]={contexts[debug_voice*16+1],contexts[debug_voice*16]};''','''        if(RAM_STEPS)begin: packed_debug
            assign gains[debug_voice*16+:16]=contexts[debug_voice*16+1][31:16];
            assign states[debug_voice*3+:3]=contexts[debug_voice*16+1][2:0];
            assign phases[debug_voice*32+:32]=contexts[debug_voice*16];
        end else begin: legacy_debug
            assign gains[debug_voice*16+:16]=contexts[debug_voice*16+3];
            assign states[debug_voice*3+:3]=contexts[debug_voice*16+2][2:0];
            assign phases[debug_voice*32+:32]={contexts[debug_voice*16+1],contexts[debug_voice*16]};
        end''')
sub('`ifndef SYNTHESIS','''`ifndef SYNTHESIS
    reg [CONTROL_KEYS*32-1:0] expected_frame_steps;
    integer check_key;
    always @(posedge clk)
        if(resetn && RAM_STEPS && sample_ce && state==IDLE)
            expected_frame_steps<=replay_select ? replay_steps : low_steps;
    always @(negedge clk)
        if(resetn && RAM_STEPS && state==LOAD && index==0)
            for(check_key=0;check_key<CONTROL_KEYS;check_key=check_key+1)
                if((!frame_legacy || check_key<7) && contexts[check_key*16+8]!==expected_frame_steps[check_key*32+:32])
                    $fatal(1,"Frame pitch capture torn at key %0d",check_key+1);''')
p.write_text(s,encoding='utf-8')
p=P/'sim/tb_control12_step_ram.v';s=p.read_text(encoding='utf-8')
sub('{dut.contexts[i*32+14],dut.contexts[i*32+13]}','{dut.contexts[i*16+7][15:0],dut.contexts[i*16+6][31:16]}')
p.write_text(s,encoding='utf-8')
print('Packed 32-bit context/step layout replaces the first two-read-port prototype')
