`timescale 1ns/1ps
module tb_control12_touch_widths #(parameter READ_MODE=0, GAIN_SHIFT=4);
    reg clk=0;always #10 clk=~clk;
    reg resetn=0;reg [9:0] divider=0;
    wire ce=divider==0;
    always @(posedge clk)divider<=divider+1'b1;
    reg [15:0] gates=0,physical=0;
    reg [1:0] pedal=0;reg [4:0] poly=16;
    reg [63:0] cfg={16'd1,16'd1,16'd32768,16'd1};
    reg [15:0] ratio=65535;
    reg [383:0] live_steps=0,replay_steps=0;
    reg replay=0,legacy=0;
    wire signed [15:0] pcm,ref_pcm;
    wire [15:0] active,ref_active;
    wire [4:0] count,ref_count;
    wire clipped,ref_clipped,overrun,ref_overrun;
    integer i,n,frame=0,cycle=0,checks=0,max_busy=0,busy_cycles=0;
    touch_tdm_synth #(.CONTROL_KEYS(12),.VOLUME_SHIFT(GAIN_SHIFT),.FAST_READ(READ_MODE),.EXTENDED_CONTROL(1)) dut(
        .clk(clk),.resetn(resetn),.sample_ce(ce),.gates(gates),.physical_gates(physical),
        .pedal_mode(pedal),.poly_limit(poly),.low_steps(replay ? replay_steps : live_steps),.legacy_high_keys(legacy),.adsr_config(cfg),.pitch_ratio(ratio),
        .sample(pcm),.active(active),.voice_count(count),.clipped(clipped),.overrun(overrun));
    touch_control12_step_reference #(.VOLUME_SHIFT(GAIN_SHIFT),.CONTROL_KEYS(12),.FAST_READ(READ_MODE),.EXTENDED_CONTROL(1)) reference(
        .clk(clk),.resetn(resetn),.sample_ce(ce),.gates(gates),.physical_gates(physical),
        .pedal_mode(pedal),.poly_limit(poly),.low_steps(replay ? replay_steps : live_steps),
        .legacy_high_keys(legacy),.adsr_config(cfg),.pitch_ratio(ratio),
        .sample(ref_pcm),.active(ref_active),.voice_count(ref_count),.clipped(ref_clipped),.overrun(ref_overrun));
    always @(negedge clk)if(resetn)begin
        if(ce)begin
            frame=frame+1;cycle=0;
            if(frame>3)begin
                if(overrun || ref_overrun)$fatal(1,"Frame deadline exceeded");
                if({pcm,active,count,clipped}!=={ref_pcm,ref_active,ref_count,ref_clipped})
                    $fatal(1,"Frame %0d differs PCM %0d/%0d active %h/%h count %0d/%0d",frame,pcm,ref_pcm,active,ref_active,count,ref_count);
                if(dut.phases!==reference.phases || dut.gains!==reference.gains || dut.states!==reference.states)
                    $fatal(1,"Frame %0d differs in DDS phase/envelope",frame);
                for(i=0;i<16;i=i+1)begin
                    if({dut.contexts[i*16+14],dut.contexts[i*16+13]}!=={reference.contexts[i*16+14],reference.contexts[i*16+13]})
                        $fatal(1,"Age mismatch frame %0d voice %0d",frame,i);
                end
                checks=checks+1;
            end
        end else cycle=cycle+1;
        // Model the real pitch scaler: updates 6 cycles apart, beginning
        // after cycle 6. Each old 32-bit word must be captured beforehand.
        if(cycle>=6 && cycle<78 && ((cycle-6)%6)==0)
            live_steps[((cycle-6)/6)*32 +: 32]=32'h1020304*(frame+1)+((cycle-6)/6)*32'h1001001;
        // TAKE changes fields only after its frame guard. Deliberately
        // change the two halves on separate clocks to expose torn reads.
        if(cycle>=34 && cycle<58)
            replay_steps[(cycle-34)*16 +: 16]=16'h2101*frame+cycle;
        if(dut.state!=1 && dut.state!=0)busy_cycles=busy_cycles+1;
        else begin if(busy_cycles>max_busy)max_busy=busy_cycles;busy_cycles=0;end
    end
    task frames;input integer amount;integer end_frame;begin end_frame=frame+amount;wait(frame>=end_frame);@(negedge clk);end endtask
    initial begin
        for(n=0;n<12;n=n+1)begin live_steps[n*32+:32]=23012828+n*1000000;replay_steps[n*32+:32]=45000000+n*2000000;end
        repeat(5)@(negedge clk);resetn=1;frames(4);
        // Simultaneous starts/attack->decay/release exercise all 16 dividers.
        gates=16'hffff;physical=gates;frames(20);gates=0;physical=0;frames(12);
        replay=1;gates=16'hffff;physical=gates;ratio=32768;frames(20);
        legacy=1;frames(12);legacy=0;ratio=65535;frames(12);
        // Pedal tails, poly stealing and ages must remain bit-identical.
        replay=0;pedal=2;poly=8;cfg={16'd3,16'd2,16'd50000,16'd5};frames(5);
        physical=0;gates=0;frames(40);gates=16'h00ff;physical=gates;frames(10);
        physical=0;gates=0;frames(40);pedal=0;frames(20);
        if(checks<180 || max_busy>1023)$fatal(1,"Insufficient stress checks or deadline");
        $display("PASS exact touch arithmetic: %0d bit-exact frames, live/replay updates, 16 DDS phases/ADSR/age/poly/tails/legacy fallback, PCM; worst busy %0d/1024 clocks",checks,max_busy);$finish;
    end
    initial begin #10000000;$fatal(1,"Touch arithmetic timeout");end
endmodule

// Frozen shared_reply source for a frame-by-frame independent comparison.
`timescale 1ns/1ps
// Sixteen independent gated DDS/ADSR contexts, one arithmetic path and
// one 256x16 context RAM. Worst-case 16 simultaneous segment divisions
// complete within the 1024-clock stereo frame. First seven retain remap/bend.
module touch_control12_step_reference #(
    parameter integer VOLUME_SHIFT=4, EXTENDED_CONTROL=0, CONTROL_KEYS=7,
    parameter integer SHARED_ARITH=0, FAST_READ=0,
    parameter integer PEDAL_TAIL_MS=1200, DAMPER_MS=10
)(
    input wire clk,resetn,sample_ce,
    input wire [15:0] gates,
    input wire [15:0] physical_gates,
    input wire [1:0] pedal_mode,
    input wire [4:0] poly_limit,
    input wire [CONTROL_KEYS*32-1:0] low_steps,
    input wire legacy_high_keys,
    input wire [63:0] adsr_config,
    input wire [15:0] pitch_ratio,
    output reg signed [15:0] sample,
    output reg [15:0] active,
    output reg [4:0] voice_count,
    output reg clipped,
    output reg overrun,
    output wire shared_mul_request, shared_sine_request,
    output wire signed [32:0] shared_mul_a,
    output wire signed [17:0] shared_mul_b,
    output wire [31:0] shared_sine_phase,
    input wire shared_mul_grant, shared_sine_grant,
    input wire signed [50:0] shared_product,
    input wire signed [15:0] shared_sine
);
    // Thirteen 16-bit words per voice fit one 18Kbit synchronous RAM.
    // Serial context reads/writes avoid a wide shallow RAM and LUT mux bank.
    (* syn_ramstyle="block_ram" *) reg [15:0] contexts[0:255];
    reg [15:0] context_q;
    reg [7:0] address,init_address;
    reg [3:0] index,field;
    reg [3:0] state;
    localparam INIT=0,IDLE=1,LOAD=2,ENV=3,DIVIDE=4,PITCH=5,PITCH_WAIT=6,
        WAVE=7,GAIN=8,GAIN_WAIT=9,STORE=10,PUBLISH=11,READ_WAIT=12,READ_WORD=13,WAVE_WAIT=14;
    reg [15:0] frame_gates;
    reg [15:0] frame_physical;
    reg [1:0] frame_pedal,tail_part,publish_part,age_load;
    reg [4:0] frame_poly,count_work,pending_work,physical_work;
    reg seen_physical,victim_valid,oldest_valid;
    reg [3:0] victim,oldest;
    reg [31:0] age,oldest_age;
    localparam [63:0] TAIL_SAMPLES=(64'd50000*PEDAL_TAIL_MS+512)/1024;
    localparam [15:0] DAMPER_SAMPLES=(64'd50000*DAMPER_MS+512)/1024;
    localparam [15:0] TAIL_QUARTER=TAIL_SAMPLES/4;
    localparam [1:0] TAIL_REMAINDER=TAIL_SAMPLES%4;
    wire [4:0] requested_poly=EXTENDED_CONTROL ? poly_limit : 5'd16;
    wire [1:0] requested_pedal=EXTENDED_CONTROL ? pedal_mode : 2'd0;
    wire [4:0] protected_limit=physical_work>frame_poly ? physical_work : frame_poly;
    wire [31:0] next_age=&age ? age : age+1'b1;
    reg [12:0] normalizer_target;
    wire [12:0] normalizer_gain;
    always @*begin
        case(voice_count)
            2:normalizer_target=2048;3:normalizer_target=1365;4:normalizer_target=1024;
            5:normalizer_target=819;6:normalizer_target=682;7:normalizer_target=585;
            8:normalizer_target=512;9:normalizer_target=455;10:normalizer_target=409;
            11:normalizer_target=372;12:normalizer_target=341;13:normalizer_target=315;
            14:normalizer_target=292;15:normalizer_target=273;16:normalizer_target=256;
            default:normalizer_target=4096;
        endcase
        if(requested_pedal!=2 && requested_poly==16)normalizer_target=4096;
    end
    // A constant PCM input removes the unused multiplier while retaining the existing slew.
    audio_master_volume u_poly_slew(.clk(clk),.resetn(resetn),.frame_ce(sample_ce),
        .sample_in(16'sd0),.target_gain(normalizer_target),.sample_out(),.applied_gain(normalizer_gain));
    function [15:0] tail_duration;
        input [1:0] part;
        begin tail_duration=TAIL_QUARTER+(part<TAIL_REMAINDER);end
    endfunction
    reg [CONTROL_KEYS*32-1:0] frame_steps;
    reg frame_legacy;
    reg [63:0] config_snapshot;
    reg [15:0] ratio_snapshot;
    reg [31:0] phase;
    reg seen;
    reg [2:0] stage;
    reg [15:0] gain,target,ticks,length,step,remainder,error,decay,sustain,release_time;
    reg [15:0] quotient;
    reg [16:0] div_remainder;
    reg [4:0] divide_left;
    reg signed [32:0] mul_a;
    reg signed [17:0] mul_b;
    reg signed [50:0] local_product;
    wire signed [50:0] product=SHARED_ARITH ? shared_product : local_product;
    reg [31:0] lookup_phase;
    wire signed [15:0] local_sine;
    wire signed [15:0] sine=SHARED_ARITH ? shared_sine : local_sine;
    assign shared_mul_a=mul_a;
    assign shared_mul_b=mul_b;
    assign shared_sine_phase=lookup_phase;
    assign shared_mul_request=SHARED_ARITH && resetn &&
        (state==PITCH_WAIT || state==GAIN_WAIT || (state==PUBLISH && publish_part==1));
    assign shared_sine_request=SHARED_ARITH && resetn && state==WAVE_WAIT;
    reg signed [23:0] sum;
    reg [15:0] context_write;
    always @*begin
        case(field)
            0:context_write=phase[15:0];1:context_write=phase[31:16];
            2:context_write={9'd0,tail_part,seen_physical,seen,stage};3:context_write=gain;
            4:context_write=target;5:context_write=ticks;6:context_write=length;
            7:context_write=step;8:context_write=remainder;9:context_write=error;
            10:context_write=decay;11:context_write=sustain;12:context_write=release_time;
            13:context_write=age[15:0];default:context_write=age[31:16];
        endcase
    end
    always @(posedge clk)begin
        if(resetn && (state==INIT || state==STORE || state==GAIN || state==GAIN_WAIT))
            contexts[state==INIT ? init_address : {index,field}]<=state==INIT ? 16'd0 : context_write;
    end
    always @(posedge clk)context_q<=contexts[address];
    wire [16:0] next_error={1'b0,error}+{1'b0,remainder};
    wire carry=next_error>={1'b0,length};
    wire [16:0] delta={1'b0,step}+carry;
    // Keep the carry/borrow through the arithmetic, then explicitly select
    // the 16-bit context word. Valid ADSR segments stay in 0..65535.
    wire [16:0] error_next=carry ? next_error-{1'b0,length} : next_error;
    wire [16:0] gain_next=target>=gain ? {1'b0,gain}+delta : {1'b0,gain}-delta;
    // Q16 gain (high keys have one extra attenuation bit). Preserve the
    // arithmetic shift before selecting the signed mixer/monitor widths.
    wire signed [50:0] scaled_product=product>>>(index<7 ? (16+VOLUME_SHIFT) : (17+VOLUME_SHIFT));
    wire signed [50:0] normalized_product=product>>>12;
    wire [16:0] shifted={div_remainder[15:0],quotient[15]};
    wire subtract=shifted>={1'b0,length};
    wire [16:0] rem_next=subtract ? shifted-{1'b0,length} : shifted;
    wire [15:0] q_next={quotient[14:0],subtract};
    touch_sine_rom u_sine(.clk(clk),.phase(lookup_phase),.sample(local_sine));
    always @(posedge clk) local_product<=mul_a*mul_b;
    function [31:0] note_step;
        input [3:0] key;
        begin case(key)
            0:note_step=34480283; 1:note_step=36530588; 2:note_step=38702809;
            3:note_step=41004198; 4:note_step=43442435; 5:note_step=46025656;
            6:note_step=51662052; 7:note_step=57988693; default:note_step=61436880;
        endcase end
    endfunction
    task segment;
        input [2:0] next_stage;
        input [15:0] end_gain, duration;
        begin
            stage<=next_stage;target<=end_gain;
            length<=duration==0 ? 16'd1 : duration;
            ticks<=duration==0 ? 16'd1 : duration;
            quotient<=(end_gain>=gain) ? end_gain-gain : gain-end_gain;
            div_remainder<=0;divide_left<=15;error<=0;state<=DIVIDE;
        end
    endtask
    always @(posedge clk) begin
        if(!resetn) begin
            state<=INIT;index<=0;sample<=0;active<=0;overrun<=0;clipped<=0;sum<=0;
            address<=0;init_address<=0;field<=0;phase<=0;seen<=0;stage<=0;gain<=0;target<=0;ticks<=0;
            length<=1;step<=0;remainder<=0;error<=0;decay<=1;sustain<=0;release_time<=1;
            frame_gates<=0;frame_steps<=0;config_snapshot<=0;ratio_snapshot<=65535;
            quotient<=0;div_remainder<=0;divide_left<=0;mul_a<=0;mul_b<=0;lookup_phase<=0;
            frame_physical<=0;frame_pedal<=0;frame_poly<=16;tail_part<=0;publish_part<=0;age_load<=0;
            count_work<=0;pending_work<=0;physical_work<=0;voice_count<=0;
            seen_physical<=0;victim_valid<=0;oldest_valid<=0;victim<=0;oldest<=0;age<=0;oldest_age<=0;
        end else begin
            if(sample_ce && state!=IDLE && state!=INIT)overrun<=1;
            // Prefetch age during arithmetic so context growth costs no voice cycles.
            if(age_load==2)begin age[15:0]<=context_q;age_load<=1;end
            else if(age_load==1)begin age[31:16]<=context_q;age_load<=0;end
            case(state)
                INIT:begin
                    if(init_address==255)begin index<=0;state<=IDLE;end else init_address<=init_address+1'b1;
                end
                IDLE:if(sample_ce)begin
                    frame_gates<=gates;frame_steps<=low_steps;frame_legacy<=legacy_high_keys;config_snapshot<=adsr_config;ratio_snapshot<=pitch_ratio;
                    frame_physical<=EXTENDED_CONTROL ? physical_gates : gates;
                    frame_pedal<=requested_pedal;frame_poly<=requested_poly;
                    count_work<=0;pending_work<=0;physical_work<=0;oldest_valid<=0;publish_part<=0;
                    index<=0;sum<=0;state<=LOAD;
                end
                LOAD:begin field<=0;address<={index,4'd0};state<=READ_WAIT;end
                READ_WAIT:begin
                    if(FAST_READ)address<=address+1'b1;
                    state<=READ_WORD;
                end
                READ_WORD:begin
                    case(field)
                        0:phase[15:0]<=context_q;1:phase[31:16]<=context_q;
                        2:{tail_part,seen_physical,seen,stage}<=context_q[6:0];3:gain<=context_q;4:target<=context_q;
                        5:ticks<=context_q;6:length<=context_q;7:step<=context_q;
                        8:remainder<=context_q;9:error<=context_q;10:decay<=context_q;
                        11:sustain<=context_q;12:release_time<=context_q;
                    endcase
                    if(field==12)begin address<={index,4'd13};state<=ENV;end
                    else begin field<=field+1'b1;address<=address+1'b1;state<=FAST_READ ? READ_WORD : READ_WAIT;end
                end
                ENV:begin
                    seen<=frame_gates[index];state<=PITCH;
                    seen_physical<=frame_physical[index];address<={index,4'd14};age_load<=2;
                    if(frame_gates[index] && (!seen ||
                       (frame_physical[index] && !seen_physical && (stage==0 || stage==6))))begin
                        decay<=config_snapshot[47:32];sustain<=config_snapshot[31:16];release_time<=config_snapshot[15:0];
                        segment(1,65535,config_snapshot[63:48]);
                    end else if(victim_valid && victim==index && !frame_physical[index] && stage!=0 && stage!=6)begin
                        segment(6,0,stage==4 && ticks<DAMPER_SAMPLES ? ticks : DAMPER_SAMPLES);
                    end else if(stage==5 && frame_pedal!=2)begin
                        segment(4,0,DAMPER_SAMPLES);
                    end else if(!frame_gates[index] && seen)begin
                        if(gain==0)stage<=0;
                        else if(frame_pedal==2)begin tail_part<=0;segment(5,gain>>2,tail_duration(0));end
                        else segment(4,0,release_time);
                    end else if(stage==1 || stage==2 || stage==4 || stage==5 || stage==6)begin
                        if(ticks<=1)begin
                            gain<=target;
                            if(stage==1)begin
                                // Attack ends at 65535; use that committed level
                                // as the origin of the decay division.
                                stage<=2;target<=sustain;length<=decay==0 ? 16'd1 : decay;
                                ticks<=decay==0 ? 16'd1 : decay;quotient<=65535-sustain;
                                div_remainder<=0;divide_left<=15;error<=0;state<=DIVIDE;
                            end else if(stage==5 && tail_part!=3)begin
                                tail_part<=tail_part+1'b1;
                                segment(5,tail_part==2 ? 16'd0 : target>>2,tail_duration(tail_part+1'b1));
                                // The previous target is the committed origin at a linked boundary.
                                quotient<=target-(tail_part==2 ? 16'd0 : target>>2);
                            end else stage<=stage==2 ? 3 : 0;
                        end else begin
                            ticks<=ticks-1'b1;error<=error_next[15:0];
                            gain<=gain_next[15:0];
                        end
                    end else if(stage==3)gain<=sustain;
                    else gain<=0;
                end
                DIVIDE:begin
                    quotient<=q_next;div_remainder<=rem_next;
                    if(divide_left==0)begin step<=q_next;remainder<=rem_next[15:0];state<=PITCH;end
                    else divide_left<=divide_left-1'b1;
                end
                PITCH:begin mul_a<=$signed({1'b0,note_step(index-4'd7)});mul_b<=$signed({2'b0,ratio_snapshot});state<=PITCH_WAIT;end
                PITCH_WAIT:if(!SHARED_ARITH || shared_mul_grant)state<=WAVE;
                WAVE:begin
                    age<=stage!=0 && !frame_physical[index] ? next_age : 0;
                    if(stage!=0 && stage!=6 && !frame_physical[index] && (!oldest_valid || next_age>oldest_age))begin
                        oldest_valid<=1;oldest<=index;oldest_age<=next_age;
                    end
                    lookup_phase<=phase;
                    phase<=phase+((index<7 || (CONTROL_KEYS>7 && !frame_legacy && index<CONTROL_KEYS)) ? frame_steps[index*32+:32] :
                        (ratio_snapshot==65535) ? note_step(index-4'd7) : product[47:16]);
                    state<=WAVE_WAIT;
                end
                WAVE_WAIT:if(!SHARED_ARITH || shared_sine_grant)begin field<=13;state<=GAIN;end
                GAIN:begin field<=14;mul_a<=$signed(sine);mul_b<=$signed({2'b0,gain});state<=GAIN_WAIT;end
                GAIN_WAIT:if(!SHARED_ARITH || shared_mul_grant)begin field<=0;state<=STORE;end
                STORE:begin
                    if(field==0)begin
                        sum<=sum+$signed(scaled_product[23:0]);active[index]<=stage!=0;
                        if(stage!=0)count_work<=count_work+1'b1;
                        if(stage==6)pending_work<=pending_work+1'b1;
                        if(frame_physical[index])physical_work<=physical_work+1'b1;
                    end
                    if(field==12)begin
                        if(index==15)state<=PUBLISH;else begin index<=index+1'b1;state<=LOAD;end
                    end else field<=field+1'b1;
                end
                PUBLISH:begin
                    if(publish_part!=1 || !SHARED_ARITH || shared_mul_grant)
                        publish_part<=publish_part+1'b1;
                    if(publish_part==0)begin
                        voice_count<=count_work;victim<=oldest;
                        victim_valid<=oldest_valid && count_work-pending_work>protected_limit;
                        mul_a<=sum;mul_b<=$signed({5'd0,normalizer_gain});
                    end else if(publish_part==2)begin
                        clipped<=normalized_product>32767 || normalized_product< -32768;
                        sample<=normalized_product>32767 ? 16'sh7fff : normalized_product< -32768 ? 16'sh8000 : normalized_product[15:0];state<=IDLE;
                    end
                end
                default:state<=INIT;
            endcase
        end
    end
`ifndef SYNTHESIS
    initial if(TAIL_SAMPLES<4 || TAIL_SAMPLES>262140 || DAMPER_MS<1 || DAMPER_MS>1342)
        $fatal(1,"Pedal duration exceeds linked 16-bit segment limits");
    reg [255:0] voice_samples;
    always @(posedge clk)begin
        if(!resetn)voice_samples<=0;
        else if(state==STORE && field==0)voice_samples[index*16+:16]<=scaled_product[15:0];
    end
    wire [255:0] gains;
    wire [47:0] states;
    wire [511:0] phases;
    genvar debug_voice;
    generate for(debug_voice=0;debug_voice<16;debug_voice=debug_voice+1)begin: debug_state
        assign gains[debug_voice*16+:16]=contexts[debug_voice*16+3];
        assign states[debug_voice*3+:3]=contexts[debug_voice*16+2][2:0];
        assign phases[debug_voice*32+:32]={contexts[debug_voice*16+1],contexts[debug_voice*16]};
    end endgenerate
`endif
endmodule
