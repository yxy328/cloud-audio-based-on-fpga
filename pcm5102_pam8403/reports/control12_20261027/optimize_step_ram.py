from pathlib import Path
R=Path(__file__).resolve().parent
P=R/'candidate/pcm5102_pam8403'
# Start from the fully validated source rather than the rejected reply trim.
p=P/'src/hc05_keymap.v'
p.write_bytes((P/'sim/build/unified/control12_shared_reply/pcm5102_pam8403/src/hc05_keymap.v').read_bytes())
p=P/'src/touch_tdm_synth.v';s=p.read_text(encoding='utf-8')
def sub(a,b):
    global s
    assert a in s,a[:100]
    s=s.replace(a,b)
sub('parameter integer SHARED_ARITH=0, FAST_READ=0,','parameter integer SHARED_ARITH=0, FAST_READ=0, RAM_STEPS=0,')
sub('input wire legacy_high_keys,','input wire legacy_high_keys,\n    input wire [CONTROL_KEYS*32-1:0] replay_steps,\n    input wire replay_select,')
sub('reg [15:0] contexts[0:255];','reg [15:0] contexts[0:(RAM_STEPS ? 512 : 256)-1];')
sub('reg [7:0] address,init_address;','reg [(RAM_STEPS ? 9 : 8)-1:0] address;\n    reg [7:0] init_address;')
sub('WAVE_WAIT=14;','WAVE_WAIT=14,SNAPSHOT=15;')
sub('reg frame_legacy;','reg frame_legacy,frame_replay;\n    reg [15:0] step_q;\n    reg [31:0] voice_step;\n    wire controlled=index<7 || (CONTROL_KEYS>7 && !frame_legacy && index<CONTROL_KEYS);\n    wire [31:0] stored_age=(RAM_STEPS && age_load==1) ? {context_q,age[15:0]} : age;\n    wire [31:0] advanced_age=&stored_age ? stored_age : stored_age+1\'b1;')
sub('''    always @(posedge clk)begin
        if(resetn && (state==INIT || state==STORE || state==GAIN || state==GAIN_WAIT))
            contexts[state==INIT ? init_address : {index,field}]<=state==INIT ? 16'd0 : context_write;
    end''','''    // Port A captures two step words per controlled voice, then becomes a
    // second read port during context loading. Port B retains context reads.
    // Both banks occupy the same physical 18K block; no new RAM is needed.
    wire context_we=resetn && (state==INIT || state==STORE || state==GAIN || state==GAIN_WAIT || (RAM_STEPS && state==SNAPSHOT));
    wire [8:0] init_word={init_address[7:4],1'b0,init_address[3:0]};
    wire [8:0] step_word={index,5'd15}+field[0];
    wire [8:0] read_step_word={index,5'd15}+((state==READ_WORD && field>=11) || (state==READ_WAIT && field>=11));
    wire [8:0] port_a_address=state==INIT ? init_word : state==SNAPSHOT ? step_word :
        context_we ? {index,1'b0,field} : read_step_word;
    wire [15:0] live_step_word=low_steps[index*32+field[0]*16 +: 16];
    wire [15:0] replay_step_word=replay_steps[index*32+field[0]*16 +: 16];
    wire [15:0] port_a_data=state==INIT ? 16'd0 : state==SNAPSHOT ?
        (frame_replay ? replay_step_word : live_step_word) : context_write;
    generate if(RAM_STEPS)begin: ram_step_port
        always @(posedge clk)begin
            if(context_we)contexts[port_a_address]<=port_a_data;
            else step_q<=contexts[port_a_address];
        end
    end else begin: old_context_port
        always @(posedge clk)begin
            if(context_we)contexts[state==INIT ? init_address : {index,field}]<=state==INIT ? 16'd0 : context_write;
        end
    end endgenerate''')
sub('frame_gates<=0;frame_steps<=0;config_snapshot<=0;ratio_snapshot<=65535;','frame_gates<=0;frame_steps<=0;frame_legacy<=0;frame_replay<=0;voice_step<=0;config_snapshot<=0;ratio_snapshot<=65535;')
sub('frame_gates<=gates;frame_steps<=low_steps;frame_legacy<=legacy_high_keys;config_snapshot<=adsr_config;ratio_snapshot<=pitch_ratio;','frame_gates<=gates;if(!RAM_STEPS)frame_steps<=low_steps;frame_legacy<=legacy_high_keys;frame_replay<=replay_select;config_snapshot<=adsr_config;ratio_snapshot<=pitch_ratio;')
sub('''                    index<=0;sum<=0;state<=LOAD;
                end
                LOAD:begin field<=0;address<={index,4'd0};state<=READ_WAIT;end''','''                    index<=0;field<=0;sum<=0;state<=RAM_STEPS ? SNAPSHOT : LOAD;
                end
                SNAPSHOT:begin
                    if(field[0])begin
                        field<=0;
                        if(index==CONTROL_KEYS-1)begin index<=0;state<=LOAD;end
                        else index<=index+1'b1;
                    end else field<=1;
                end
                LOAD:begin field<=0;address<=RAM_STEPS ? {index,5'd0} : {index,4'd0};state<=READ_WAIT;end''')
sub('''                    if(field==12)begin address<={index,4'd13};state<=ENV;end''','''                    if(RAM_STEPS && field==11)voice_step[15:0]<=step_q;
                    if(RAM_STEPS && field==12)voice_step[31:16]<=step_q;
                    if(field==12)begin address<=RAM_STEPS ? {index,5'd13} : {index,4'd13};state<=ENV;end''')
sub('seen<=frame_gates[index];state<=PITCH;','seen<=frame_gates[index];state<=RAM_STEPS && controlled ? WAVE : PITCH;')
sub('seen_physical<=frame_physical[index];address<={index,4\'d14};age_load<=2;',"seen_physical<=frame_physical[index];address<=RAM_STEPS ? {index,5'd14} : {index,4'd14};age_load<=2;")
sub('remainder<=rem_next[15:0];state<=PITCH;','remainder<=rem_next[15:0];state<=RAM_STEPS && controlled ? WAVE : PITCH;')
sub('''                    age<=stage!=0 && !frame_physical[index] ? next_age : 0;
                    if(stage!=0 && stage!=6 && !frame_physical[index] && (!oldest_valid || next_age>oldest_age))begin
                        oldest_valid<=1;oldest<=index;oldest_age<=next_age;
                    end''','''                    if(!RAM_STEPS)begin
                        age<=stage!=0 && !frame_physical[index] ? next_age : 0;
                        if(stage!=0 && stage!=6 && !frame_physical[index] && (!oldest_valid || next_age>oldest_age))begin
                            oldest_valid<=1;oldest<=index;oldest_age<=next_age;
                        end
                    end''')
sub('phase<=phase+((index<7 || (CONTROL_KEYS>7 && !frame_legacy && index<CONTROL_KEYS)) ? frame_steps[index*32+:32] :','phase<=phase+(controlled ? (RAM_STEPS ? voice_step : frame_steps[index*32+:32]) :')
sub('''                WAVE_WAIT:if(!SHARED_ARITH || shared_sine_grant)begin field<=13;state<=GAIN;end''','''                WAVE_WAIT:begin
                    // With a pre-scaled pitch there is no multiplier wait.
                    // Complete the age prefetch here before GAIN writes it.
                    if(RAM_STEPS && field==12)begin
                        age<=stage!=0 && !frame_physical[index] ? advanced_age : 0;
                        if(stage!=0 && stage!=6 && !frame_physical[index] && (!oldest_valid || advanced_age>oldest_age))begin
                            oldest_valid<=1;oldest<=index;oldest_age<=advanced_age;
                        end
                        field<=13;
                    end
                    if(!SHARED_ARITH || shared_sine_grant)begin field<=13;state<=GAIN;end
                end''')
sub('contexts[debug_voice*16+', 'contexts[debug_voice*(RAM_STEPS ? 32 : 16)+')
sub('contexts[debug_voice*16]', 'contexts[debug_voice*(RAM_STEPS ? 32 : 16)]')
p.write_text(s,encoding='utf-8')
p=P/'src/top.v';s=p.read_text(encoding='utf-8')
sub('.SHARED_ARITH(SHARED_SYNTH),.FAST_READ(SHARED_SYNTH),','.SHARED_ARITH(SHARED_SYNTH),.FAST_READ(SHARED_SYNTH),.RAM_STEPS(CONTROL_KEYS==12),')
sub('.gates(touch_note_gates),.low_steps(perf_replay ? replay_steps : touch_phase_increments[CONTROL_KEYS*32-1:0]),.legacy_high_keys(perf_replay && perf_legacy),','.gates(touch_note_gates),.low_steps(CONTROL_KEYS==12 ? touch_phase_increments[CONTROL_KEYS*32-1:0] : (perf_replay ? replay_steps : touch_phase_increments[CONTROL_KEYS*32-1:0])),.legacy_high_keys(perf_replay && perf_legacy),\n        .replay_steps(replay_steps),.replay_select(perf_replay),')
sub('.WORDS(TAKE_WORDS),.GATE_WORD(32),.LEGACY_WORDS(33)', '.WORDS(TAKE_WORDS),.GATE_WORD(32),.LEGACY_WORDS(33),.FRAME_GUARD(CONTROL_KEYS==12 ? 32 : 0)')
p.write_text(s,encoding='utf-8')
p=P/'src/performance_take.v';s=p.read_text(encoding='utf-8')
sub('GATE_WORD=WORDS-1, LEGACY_WORDS=WORDS','GATE_WORD=WORDS-1, LEGACY_WORDS=WORDS, FRAME_GUARD=0')
sub('wire event_due;','''wire event_due;
    wire frame_start;
    generate if(FRAME_GUARD>0)begin: frame_guard
        reg [$clog2(FRAME_GUARD+1)-1:0] left;
        always @(posedge clk)
            if(!resetn)left<=0;
            else if(frame_ce)left<=FRAME_GUARD;
            else if(left!=0)left<=left-1'b1;
        assign frame_start=left==1;
    end else assign frame_start=frame_ce;endgenerate''')
sub('(group_active || frame_ce || held[23:16]==8\'hff)',"(group_active || frame_start || held[23:16]==8'hff)")
p.write_text(s,encoding='utf-8')
print('Serial frame-step capture shares the context block; replay starts after the 24-clock capture guard')
