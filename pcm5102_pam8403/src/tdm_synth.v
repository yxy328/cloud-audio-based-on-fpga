`timescale 1ns/1ps
// 32 independent voice contexts share one signed 33x18 multiplier and one
// sine lookup. One sample is completed within the 1024-clock I2S frame.
// The FIFO snapshots its write pointer at each frame boundary. New events
// arriving during calculation therefore belong to the following frame.
module tdm_synth #(
    parameter integer VOICES=32,
    parameter integer RUNTIME_ADSR=0,
    parameter integer VOLUME_SHIFT=4,
    parameter integer EXTENDED_TIMBRES=0,
    parameter integer SHARED_ARITH=0,
    // Sensor producers choose duration solely from the latched timbre.
    // In that integration, queue the timbre and reconstruct its duration,
    // avoiding 17 redundant bits in every FIFO entry. Generic users retain
    // the full event_frames interface with this parameter disabled.
    parameter integer PRESET_FRAMES=0,
    parameter [16:0] NOTE_FRAMES=14648,PIANO_FRAMES=58594,
        FLUTE_FRAMES=24414,UKULELE_FRAMES=34180,DRUM_FRAMES=19531,
    parameter [16:0] CHORD_FRAMES=17'd97656,
    parameter [16:0] TEST_FRAMES=17'd131071
)(
    input wire clk, resetn, sample_ce,
    input wire event_valid, chord_valid, test_valid, vibrato_enabled,
    input wire [31:0] vibrato_inc,
    input wire [9:0] vibrato_depth,
    input wire [15:0] vibrato_delay,
    input wire vibrato_update,
    input wire [15:0] tuning_ratio,
    input wire [31:0] event_inc,
    input wire [2:0] event_timbre,
    input wire [16:0] event_frames,
    input wire [129:0] event_adsr,
    output reg [31:0] voice_active,
    output reg [5:0] voice_count,
    output reg signed [15:0] sample,
    output reg overrun,
    output wire busy,
    output wire event_ready,
    output wire shared_mul_request, shared_sine_request,
    output wire signed [32:0] shared_mul_a,
    output wire signed [17:0] shared_mul_b,
    output wire [31:0] shared_sine_phase,
    input wire signed [50:0] shared_product,
    input wire signed [15:0] shared_sine
);
    // Sixteen 36-bit words per voice use the full depth of one 18K RAM.
    // Port A prefetches a voice while the previous voice is calculated;
    // port B drains its updated context during the next calculation.
    localparam integer CONTEXT_BITS=556, CONTEXT_PAD=576;
    (* syn_ramstyle="block_ram" *) reg [35:0] contexts [0:VOICES*16-1];
    reg [35:0] context_q;
    reg [CONTEXT_BITS-1:0] context_work;
    reg [CONTEXT_PAD-1:0] prefetch;
    wire [CONTEXT_PAD-1:0] assembled_context={context_q,prefetch[575:36]};
    reg [4:0] slot,init_slot,read_slot;
    reg [3:0] init_word,read_word,event_word;
    reg read_running,read_valid;
    reg [3:0] read_tag;
    // Simulation/debug accessor; never part of the synthesised datapath.
    function [364:0] peek_context;
        input [4:0] index;
        reg [CONTEXT_PAD-1:0] full_context;
        integer word;
        begin
            for(word=0;word<16;word=word+1)
                full_context[word*36 +:36]=contexts[index*16+word];
            peek_context=full_context[364:0];
        end
    endfunction
    // Extended context is ABOVE the original 365-bit payload so existing
    // oscillator debug offsets remain stable. Each voice owns its snapshot.
    wire env_enabled;
    wire [128:0] env_cfg;
    wire [2:0] env_state;
    wire [15:0] env_left;
    wire [23:0] env_phase;
    wire [8:0] env_start,env_target;
    assign {env_enabled,env_cfg,env_state,env_left,env_phase,env_start,env_target}=context_work[555:365];
    wire [15:0] env_a=env_cfg[128:113],env_d=env_cfg[112:97],env_r=env_cfg[96:81];
    wire [8:0] env_s=env_cfg[80:72];
    wire [23:0] env_step=(env_state==1) ? env_cfg[71:48] : (env_state==2) ? env_cfg[47:24] : env_cfg[23:0];
    wire [24:0] env_sum={1'b0,env_phase}+{1'b0,env_step};
    wire [23:0] env_advance=env_sum[24] ? 24'hffffff : env_sum[23:0];
    wire signed [9:0] env_delta=$signed({1'b0,env_target})-$signed({1'b0,env_start});
    reg signed [15:0] env_ramp_gain;
    reg [2:0] n_env_state;
    reg [15:0] n_env_left;
    reg [23:0] n_env_phase;
    reg [8:0] n_env_start,n_env_target;
    reg [129:0] request_adsr;
    reg pending;
    reg [5:0] delay_frames;
    reg [31:0] pending_inc, note_inc;
    reg [2:0] pending_timbre, note_timbre;
    reg [16:0] pending_frames, remaining;
    reg [8:0] gain, stage_gain, frame_gain;
    reg [23:0] body_env, bright_env;
    reg [31:0] phase, aux_phase, aux2_phase, drum_glide;
    reg [16:0] noise_state;
    reg signed [17:0] air_low;
    reg signed [15:0] prev_pcm;
    always @(*) begin
        {pending,delay_frames,pending_inc,pending_timbre,pending_frames,
         note_inc,note_timbre,remaining,gain,body_env,bright_env,
         phase,aux_phase,aux2_phase,drum_glide,noise_state,air_low,
         prev_pcm,stage_gain,frame_gain}=context_work[364:0];
    end

    // 64 commands; a chord/test occupies one entry and expands internally.
    localparam integer FIFO_BITS=PRESET_FRAMES ? 167 : 184;
    (* syn_ramstyle="block_ram" *) reg [FIFO_BITS-1:0] fifo [0:63];
    reg [6:0] write_ptr, read_ptr, frame_limit;
    reg [FIFO_BITS-1:0] fifo_q;
    reg [183:0] command;
    function [16:0] frames_for_timbre;
        input [2:0] timbre;
        begin case(timbre)
            1,5:frames_for_timbre=PIANO_FRAMES;
            2,7:frames_for_timbre=FLUTE_FRAMES;
            3,6:frames_for_timbre=UKULELE_FRAMES;
            4:frames_for_timbre=DRUM_FRAMES;
            default:frames_for_timbre=NOTE_FRAMES;
        endcase end
    endfunction
    wire fifo_full = (write_ptr-read_ptr)==7'd64;
    assign event_ready = !fifo_full;
    wire incoming = test_valid || chord_valid || event_valid;
    wire [1:0] incoming_type = test_valid ? 2'd2 : chord_valid ? 2'd1 : 2'd0;
    wire [183:0] fifo_input={(RUNTIME_ADSR && !test_valid) ? event_adsr : 130'd0,
        incoming_type,event_frames,event_timbre,event_inc};
    wire [183:0] fifo_command;
    generate if(PRESET_FRAMES)begin: preset_fifo
        assign fifo_command={fifo_q[166:35],frames_for_timbre(fifo_q[34:32]),fifo_q[34:0]};
    end else begin: general_fifo
        assign fifo_command=fifo_q;
    end endgenerate
    always @(posedge clk) begin
        fifo_q <= fifo[read_ptr[5:0]];
        if (!resetn) begin write_ptr<=0; end
        else if (incoming && !fifo_full) begin
            fifo[write_ptr[5:0]] <= PRESET_FRAMES ? {fifo_input[183:52],fifo_input[34:0]} : fifo_input;
            write_ptr <= write_ptr+1'b1;
        end
    end
    reg command_active;
    reg [5:0] sub_note, event_quota;
    reg [31:0] request_inc;
    reg [2:0] request_timbre;
    reg [16:0] request_frames;
    // Most-recent to least-recent slot IDs. Moving one entry to the front
    // replaces 32 parallel rank incrementers and a rank[slot] multiplexer.
    // Free-slot preference and the exact oldest-voice policy are unchanged.
    reg [4:0] rank_order [0:VOICES-1];
    wire [VOICES:0] shift_rank;
    assign shift_rank[0]=1'b1;
    genvar rank_index;
    generate for(rank_index=0;rank_index<VOICES;rank_index=rank_index+1)begin: rank_prefix
        assign shift_rank[rank_index+1]=shift_rank[rank_index] && rank_order[rank_index]!=slot;
    end endgenerate
    reg [4:0] allocation;
    integer a;
    always @(*) begin
        allocation=rank_order[VOICES-1];
        for (a=VOICES-1;a>=0;a=a-1) if(!voice_active[a]) allocation=a;
    end
    function [31:0] test_pitch;
        input [4:0] n;
        begin
            // Distinct coherent bins 37,44,...,254 of a 4096-point FFT.
            // f=(37+7*n)*Fs/4096; no harmonic components counted as voices.
            test_pitch=(32'd37+({27'd0,n}<<3)-{27'd0,n})<<20;
        end
    endfunction
    reg [31:0] command_inc;
    always @(*) begin
        command_inc=command[31:0];
        if(command[53:52]==1) begin
            case(sub_note[1:0])
                0:command_inc=23012828; 1:command_inc=28994347;
                2:command_inc=34480283; 3:command_inc=43442435;
            endcase
        end else if(command[53:52]==2) command_inc=test_pitch(sub_note[4:0]);
    end

    localparam [5:0] INIT=0, IDLE=1, LFO1=2, LFO2=3, LFO3=4, LFO4=5,
        EVENT_READY=6, COMMAND_FETCH=7, EVENT_PATCH=8, EVENT_COMMIT=10,
        VOICE_PRIME=11, VOICE_ACCEPT=12, LOOK_BASE=13, LOOK_H2=14, LOOK_H3=15,
        LOOK_H4=16, LOOK_AUX=17, LOOK_AUX2=18, PITCH_MUL=19, PITCH_WAIT=20,
        BODY_MUL=21, BODY_WAIT=22, BRIGHT_MUL=23, BRIGHT_WAIT=24,
        GAIN_MUL=25, GAIN_WAIT=26, VOICE_COMMIT=27, PUBLISH=28, VOICE_DRAIN=29;
    reg [5:0] state;
    assign busy = state!=IDLE;
    reg [31:0] lfo_phase, lookup_phase, phase_step;
    reg [15:0] frame_tuning;
    reg [9:0] depth;
    reg signed [17:0] lfo_scaled;
    reg [15:0] vibrato_wait;
    always @(posedge clk)begin
        if(!resetn || vibrato_update || !vibrato_enabled)vibrato_wait<=vibrato_delay;
        else if(state==LFO1 && vibrato_wait!=0)vibrato_wait<=vibrato_wait-1'b1;
    end
    // Prefetch the next lookup at the same state edge that previously
    // registered lookup_phase. This retains the arithmetic schedule while
    // mapping the exact legacy 256-point table into one block ROM.
    (* syn_romstyle="block_rom" *) reg [15:0] sine_table[0:255];
    initial $readmemh("src/tdm_sine256.hex",sine_table);
    reg signed [15:0] local_lookup_sample;
    wire signed [15:0] lookup_sample=SHARED_ARITH ? shared_sine : local_lookup_sample;
    reg [31:0] lookup_request;
    always @*begin
        case(state)
            IDLE:lookup_request=lfo_phase;
            LOOK_BASE:lookup_request=phase;
            LOOK_H2:lookup_request=phase<<1;
            LOOK_H3:lookup_request=phase+(phase<<1);
            LOOK_H4:lookup_request=phase<<2;
            LOOK_AUX:lookup_request=aux_phase;
            LOOK_AUX2:lookup_request=aux2_phase;
            default:lookup_request=0;
        endcase
    end
    always @(posedge clk)local_lookup_sample<=sine_table[lookup_request[31:24]];
    assign shared_sine_phase={lookup_request[31:24],24'd0};
    assign shared_sine_request=SHARED_ARITH && resetn &&
        ((state==IDLE && sample_ce) || (state>=LOOK_BASE && state<=LOOK_AUX2));
    reg signed [17:0] base,h2,h3,h4,aux,aux2;
    reg signed [32:0] mul_a;
    reg signed [17:0] mul_b;
    reg signed [50:0] local_mul_product;
    wire signed [50:0] mul_product=SHARED_ARITH ? shared_product : local_mul_product;
    assign shared_mul_a=mul_a;
    assign shared_mul_b=mul_b;
    // LOOK_AUX2 reserves the tuning result until PITCH_MUL consumes it.
    // All other products are consumed on the immediately following edge.
    assign shared_mul_request=SHARED_ARITH && resetn &&
        (state==LFO2 || state==LOOK_H2 || state==PITCH_WAIT ||
         state==BODY_WAIT || state==BRIGHT_WAIT || state==GAIN_WAIT ||
         (frame_tuning!=16384 && (state==LOOK_AUX || state==LOOK_AUX2)));
    wire signed [50:0] pitch_delta=mul_product>>>21;
    wire signed [50:0] adjusted_pitch=$signed({{18{mul_a[32]}},mul_a})+pitch_delta;
    // The only variable multiplication in this module. Every timbre, voice,
    // envelope and vibrato operation uses this registered arithmetic path.
    always @(posedge clk) begin
        if(!resetn) local_mul_product<=0;
        else local_mul_product<=mul_a*mul_b;
    end
    reg signed [34:0] body_product;
    wire signed [35:0] combined =
        $signed({body_product[34],body_product})+
        $signed({mul_product[34],mul_product[34:0]});
    wire signed [15:0] unscaled_wave=(note_timbre==0) ? base[15:0] : combined[31:16];
    wire signed [50:0] amplified=mul_product >>> (8+VOLUME_SHIFT);
    reg signed [21:0] mix;
    wire signed [21:0] next_mix=mix+{{6{prev_pcm[15]}},prev_pcm};
    wire signed [15:0] noise=noise_state[15:0];
    wire signed [17:0] noise_wide={{2{noise[15]}},noise};
    wire signed [17:0] air_high=noise_wide-air_low;
    reg signed [17:0] body_wave,bright_wave;
    reg signed [17:0] body0,body1,body2,body3,body4,body5,bright0,bright1,bright2;
    always @(*) begin
        // Shared adder trees, with timbre selection on their operands.
        // Arithmetic stays 18-bit signed, including every intermediate
        // wrap, exactly as in the original per-timbre expressions.
        body0=0;body1=0;body2=0;body3=0;body4=0;body5=0;
        bright0=0;bright1=0;bright2=0;
        case(note_timbre)
            0:body0=base;
            1:begin body0=base>>>1;body1=base>>>2;bright0=h2>>>3;bright1=h3>>>4;bright2=h4>>>4;end
            2:begin body0=base>>>1;body1=base>>>2;body2=h2>>>3;body3=h3>>>4;body4=air_high>>>7;end
            3:begin body0=base>>>1;body1=h2>>>2;bright0=h3>>>3;bright1=h4>>>4;bright2=noise_wide>>>5;end
            4:begin body0=aux>>>1;body1=aux>>>2;body2=aux>>>3;bright0=noise_wide>>>4;end
            5:if(EXTENDED_TIMBRES)begin body0=base>>>1;body1=h2>>>3;bright0=h3>>>2;bright1=h4>>>4;end
            6:if(EXTENDED_TIMBRES)begin body0=base>>>1;bright0=aux>>>2;bright1=aux2>>>3;end
            7:if(EXTENDED_TIMBRES)begin body0=base>>>2;body1=base>>>3;body2=aux>>>2;body3=h2>>>3;body4=h3>>>4;body5=h4>>>5;end
        endcase
        body_wave=((body0+body1)+(body2+body3))+(body4+body5);
        bright_wave=bright0+bright1+bright2;
    end

    reg n_pending;
    reg [5:0] n_delay;
    reg [31:0] n_inc,n_phase,n_aux,n_aux2,n_glide;
    reg [2:0] n_timbre;
    reg [16:0] n_remaining;
    reg [8:0] n_gain;
    reg [23:0] n_body,n_bright;
    // Select decay operands before the subtractors. The prior case table
    // inferred a separate pair of 24-bit subtractors for each timbre.
    reg [12:0] body_loss;
    reg [15:0] bright_loss;
    always @*begin
        body_loss=0;bright_loss=0;
        case(note_timbre)
            1:begin body_loss=body_env>>14;bright_loss=bright_env>>11;end
            3:begin body_loss=body_env>>13;bright_loss=bright_env>>10;end
            4:begin body_loss=body_env>>11;bright_loss=bright_env>>8;end
            5:begin body_loss=body_env>>15;bright_loss=bright_env>>11;end
            6:begin body_loss=body_env>>15;bright_loss=bright_env>>13;end
        endcase
    end
    wire decay_timbre=note_timbre==1 || note_timbre==3 || note_timbre==4 ||
        (EXTENDED_TIMBRES && (note_timbre==5 || note_timbre==6));
    wire [13:0] body_decrement={1'b0,body_loss}+14'd1;
    wire [16:0] bright_decrement={1'b0,bright_loss}+17'd1;
    // Exact integer identities move constant multiply/add paths to spare
    // DSP arithmetic. Correct the discarded low-bit carries explicitly.
    (* syn_dspstyle="dsp" *) wire [37:0] bell_sum=phase_step*6'd43+{aux2_phase,3'd0};
    wire [31:0] bell_next=bell_sum[34:3]-((phase_step[2:0]==3 || phase_step[2:0]>=6) ? 32'd1 : 32'd0);
    (* syn_dspstyle="dsp" *) wire [41:0] string_sum=phase_step*9'd257+{aux_phase,8'd0};
    (* syn_dspstyle="dsp" *) wire [35:0] metal_sum=phase_step*4'd11+{aux_phase,2'd0};
    wire [31:0] metal_next=metal_sum[33:2]-(phase_step[1:0]==3 ? 32'd1 : 32'd0);
    wire [31:0] aux_advanced=note_timbre==6 ? metal_next : note_timbre==7 ? string_sum[39:8] :
        (aux_phase+phase_step)+drum_glide;
    always @(*) begin
        n_env_state=env_state;n_env_left=env_left;n_env_phase=env_phase;
        n_env_start=env_start;n_env_target=env_target;
        n_pending=pending; n_delay=delay_frames; n_inc=note_inc; n_timbre=note_timbre;
        n_remaining=remaining; n_gain=gain; n_body=body_env; n_bright=bright_env;
        n_phase=phase+phase_step; n_aux=aux_phase; n_aux2=aux2_phase; n_glide=drum_glide;
        case(note_timbre)
            4:n_aux=aux_advanced;
            6:if(EXTENDED_TIMBRES) begin
                n_aux=aux_advanced;
                n_aux2=bell_next;
            end
            7:if(EXTENDED_TIMBRES) n_aux=aux_advanced;
        endcase
        if(pending) begin
            if(delay_frames!=0) n_delay=delay_frames-1'b1;
            n_gain=(gain>8) ? gain-9'd8 : 9'd0;
        end else if(RUNTIME_ADSR && env_enabled) begin
            if(remaining!=0) n_remaining=remaining-1'b1;
            if(remaining==0 && env_state!=4 && env_state!=0) begin
                n_env_state=4;n_env_left=env_r;n_env_phase=0;n_env_start=gain;n_env_target=0;
            end else if(env_state==1 || env_state==2 || env_state==4) begin
                if(env_left<=1) begin
                    n_gain=env_target;n_env_phase=0;
                    if(env_state==1) begin
                        n_env_state=2;n_env_left=env_d;n_env_start=256;n_env_target=env_s;
                    end else if(env_state==2) n_env_state=3;
                    else n_env_state=0;
                end else begin
                    n_env_left=env_left-1'b1;n_env_phase=env_advance;
                    n_gain=(env_ramp_gain<0) ? 9'd0 : (env_ramp_gain>256) ? 9'd256 : env_ramp_gain[8:0];
                end
            end else if(env_state==3) n_gain=env_s;
            else n_gain=0;
        end else if(remaining!=0) begin
            n_remaining=remaining-1'b1;
            if(gain<256) n_gain=gain+1'b1;
        end else if(gain!=0) n_gain=gain-1'b1;
        if(decay_timbre)begin
            if(body_env!=0)n_body=body_env-{10'd0,body_decrement};
            if(bright_env!=0)n_bright=bright_env-{7'd0,bright_decrement};
        end
        case(note_timbre)
            2:n_body=(body_env<24'hFFC000) ? body_env+24'd16384 : 24'hFFFFFF;
            4:begin
                if(drum_glide!=0) n_glide=drum_glide-(drum_glide>>8)-1'b1;
            end
            7:if(EXTENDED_TIMBRES) n_body=(body_env<24'hFFE000) ? body_env+24'd8192 : 24'hFFFFFF;
        endcase
        if(pending && delay_frames==0) begin
            n_pending=0; n_inc=pending_inc; n_timbre=pending_timbre;
            n_remaining=pending_frames; n_gain=0; n_phase=0;
            n_env_state=1;n_env_left=env_a;n_env_phase=0;n_env_start=0;n_env_target=256; n_aux=0; n_aux2=0;
            n_body=(pending_timbre==2 || (EXTENDED_TIMBRES && pending_timbre==7)) ? 24'd0 : 24'hFFFFFF;
            n_bright=24'hFFFFFF; n_glide=pending_inc<<1;
        end
    end
    wire [16:0] n_noise={noise_state[15:0],noise_state[16]^noise_state[13]};
    wire signed [17:0] n_air=air_low+(air_high>>>3);
    wire n_active=n_pending || n_remaining!=0 || n_gain!=0 || gain!=0 || stage_gain!=0;
    wire [CONTEXT_BITS-1:0] stepped_context={
        env_enabled,env_cfg,n_env_state,n_env_left,n_env_phase,n_env_start,n_env_target,
        n_pending,n_delay,pending_inc,pending_timbre,pending_frames,
        n_inc,n_timbre,n_remaining,n_gain,n_body,n_bright,n_phase,n_aux,n_aux2,
        n_glide,n_noise,n_air,amplified[15:0],gain,stage_gain};
    // Event allocation changes only pending-note, remaining-time and ADSR
    // words. Four boundary words are read/modified; full words need no read.
    reg [35:0] event_data;
    always @*begin
        case(event_word)
            7:event_data={context_q[35:19],17'd0,context_q[1:0]};
            8:event_data={request_timbre[0],request_frames,context_q[17:0]};
            9:event_data={2'd0,request_inc,request_timbre[2:1]};
            10:event_data={context_q[35:5],1'b1,4'd8};
            11:event_data={request_adsr[5:0],context_q[29:0]};
            12:event_data=request_adsr[41:6];
            13:event_data=request_adsr[77:42];
            14:event_data=request_adsr[113:78];
            default:event_data={20'd0,request_adsr[129:114]};
        endcase
    end
    wire [16:0] init_number={12'd0,init_slot};
    wire [16:0] init_seed=17'h1ACE1 ^ ((init_number<<12)+(init_number<<9)+
        (init_number<<5)+(init_number<<4)+(init_number<<2));
    reg [8:0] context_read_address;
    always @*begin
        context_read_address={read_slot,read_word};
        if(state==EVENT_READY)context_read_address={allocation,4'd7};
        else if(state==EVENT_PATCH)begin
            case(event_word)
                7:context_read_address={slot,4'd8};
                8,9:context_read_address={slot,4'd10};
                10:context_read_address={slot,4'd11};
                default:context_read_address={slot,4'd0};
            endcase
        end
    end
    // Update each word as soon as its result is ready. Immutable ADSR
    // words 12..15 need no frame write. Scheduling the remaining twelve
    // words across the arithmetic states removes the 576-bit output buffer
    // and the final sixteen-clock drain without changing sample values.
    reg voice_we;
    reg [3:0] voice_write_word;
    reg [35:0] voice_write_data;
    always @*begin
        voice_we=1;voice_write_word=0;voice_write_data=0;
        case(state)
            LOOK_BASE:begin voice_write_word=9;voice_write_data=stepped_context[324 +:36];end
            LOOK_H2:begin voice_write_word=10;voice_write_data=stepped_context[360 +:36];end
            LOOK_H3:begin voice_write_word=11;voice_write_data=stepped_context[396 +:36];end
            LOOK_H4:begin voice_write_word=7;voice_write_data=stepped_context[252 +:36];end
            LOOK_AUX:begin voice_write_word=6;voice_write_data=stepped_context[216 +:36];end
            LOOK_AUX2:begin voice_write_word=8;voice_write_data=stepped_context[288 +:36];end
            PITCH_MUL:begin voice_write_word=1;voice_write_data=stepped_context[36 +:36];end
            BODY_WAIT:begin voice_write_word=2;voice_write_data=stepped_context[72 +:36];end
            BRIGHT_MUL:begin voice_write_word=3;voice_write_data=stepped_context[108 +:36];end
            BRIGHT_WAIT:begin voice_write_word=4;voice_write_data=stepped_context[144 +:36];end
            GAIN_MUL:begin voice_write_word=5;voice_write_data=stepped_context[180 +:36];end
            VOICE_COMMIT:begin voice_write_word=0;voice_write_data=stepped_context[0 +:36];end
            default:voice_we=0;
        endcase
    end
    wire context_we=state==INIT || state==EVENT_PATCH || voice_we;
    wire [8:0] context_write_address=state==INIT ? {init_slot,init_word} :
        state==EVENT_PATCH ? {slot,event_word} : {slot,voice_write_word};
    wire [35:0] context_write_data=state==INIT ?
        (init_word==1 ? {3'd0,init_seed,16'd0} : 36'd0) :
        state==EVENT_PATCH ? event_data : voice_write_data;
    always @(posedge clk)begin
        context_q<=contexts[context_read_address];
        if(resetn && context_we)contexts[context_write_address]<=context_write_data;
    end

    integer r;
    always @(posedge clk) begin
        if(!resetn) begin
            state<=INIT; init_slot<=0; init_word<=0; slot<=0;
            read_slot<=0;read_word<=0;read_running<=0;read_valid<=0;read_tag<=0;
            event_word<=0;
            read_ptr<=0; frame_limit<=0; command<=0; command_active<=0;
            request_adsr<=0;env_ramp_gain<=0;sub_note<=0; event_quota<=0; request_inc<=0; request_timbre<=0; request_frames<=0;
            voice_active<=0; voice_count<=0; sample<=0; mix<=0; overrun<=0;
            lfo_phase<=0; lookup_phase<=0; depth<=0; lfo_scaled<=0;
            frame_tuning<=16384;
            base<=0; h2<=0; h3<=0; h4<=0; aux<=0; aux2<=0;
            mul_a<=0; mul_b<=0; body_product<=0; phase_step<=0;
            for(r=0;r<VOICES;r=r+1) rank_order[r]<=r;
        end else begin
            read_valid<=read_running;
            read_tag<=read_word;
            if(read_running)begin
                if(read_word==15)begin
                    read_word<=0;
                    if(read_slot==VOICES-1)read_running<=0;
                    else read_slot<=read_slot+1'b1;
                end else read_word<=read_word+1'b1;
            end
            if(read_valid)prefetch<=assembled_context;
            if((incoming && fifo_full) || (sample_ce && state!=IDLE && state!=INIT)) overrun<=1;
            case(state)
                INIT:begin
                    if(init_word==15)begin
                        init_word<=0;
                        if(init_slot==VOICES-1)state<=IDLE;
                        else init_slot<=init_slot+1'b1;
                    end else init_word<=init_word+1'b1;
                end
                IDLE:if(sample_ce) begin
                    frame_limit<=write_ptr; mix<=0; event_quota<=0;
                    lookup_phase<=lfo_phase; lfo_phase<=lfo_phase+vibrato_inc;
                    frame_tuning<=tuning_ratio;
                    state<=LFO1;
                end
                LFO1:begin
                    mul_a<={{17{lookup_sample[15]}},lookup_sample};
                    mul_b<={8'd0,depth}; state<=LFO2;
                    if(vibrato_enabled && vibrato_wait==0 && depth<vibrato_depth)depth<=depth+1'b1;
                    else if((!vibrato_enabled || vibrato_wait!=0 || depth>vibrato_depth) && depth!=0)depth<=depth-1'b1;
                end
                LFO2:state<=LFO3;
                LFO3:begin lfo_scaled<=mul_product[25:8]; state<=LFO4; end
                LFO4:state<=EVENT_READY;
                EVENT_READY:begin
                    if(event_quota==32 || (!command_active && read_ptr==frame_limit)) begin
                        slot<=0;read_slot<=0;read_word<=0;read_running<=1;
                        state<=VOICE_PRIME;
                    end else if(!command_active) state<=COMMAND_FETCH;
                    else begin
                        slot<=allocation; request_inc<=command_inc;request_adsr<=RUNTIME_ADSR ? command[183:54] : 130'd0;
                        request_timbre<=(command[53:52]==2) ? 3'd0 : command[34:32];
                        request_frames<=(command[53:52]==2) ? TEST_FRAMES :
                                        (command[53:52]==1) ? CHORD_FRAMES : command[51:35];
                        event_word<=7;state<=EVENT_PATCH;
                    end
                end
                COMMAND_FETCH:begin
                    command<=fifo_command; read_ptr<=read_ptr+1'b1; command_active<=1; sub_note<=0;
                    state<=EVENT_READY;
                end
                EVENT_PATCH:begin
                    if(event_word==15)state<=EVENT_COMMIT;
                    else event_word<=event_word+1'b1;
                end
                EVENT_COMMIT:begin
                    if(!voice_active[slot]) voice_count<=voice_count+1'b1;
                    voice_active[slot]<=1;
                    rank_order[0]<=slot;
                    for(r=1;r<VOICES;r=r+1)
                        if(shift_rank[r])rank_order[r]<=rank_order[r-1];
                    event_quota<=event_quota+1'b1; sub_note<=sub_note+1'b1;
                    if(command[53:52]==0 || (command[53:52]==1 && sub_note==3) ||
                       (command[53:52]==2 && sub_note==VOICES-1)) command_active<=0;
                    state<=EVENT_READY;
                end
                VOICE_PRIME,VOICE_ACCEPT:if(read_valid && read_tag==15)begin
                    context_work<=assembled_context[555:0];state<=LOOK_BASE;
                end
                LOOK_BASE:begin
                    lookup_phase<=phase;state<=LOOK_H2;
                    mul_a<={9'd0,env_advance};mul_b<={{8{env_delta[9]}},env_delta};
                end
                LOOK_H2:begin base<={{2{lookup_sample[15]}},lookup_sample}; lookup_phase<=phase<<1; state<=LOOK_H3; end
                LOOK_H3:begin
                    env_ramp_gain<=$signed({7'd0,env_start})+$signed(mul_product[39:24]);
                    h2<={{2{lookup_sample[15]}},lookup_sample}; lookup_phase<=phase+(phase<<1); state<=LOOK_H4; end
                LOOK_H4:begin
                    h3<={{2{lookup_sample[15]}},lookup_sample};lookup_phase<=phase<<2;state<=LOOK_AUX;
                    // Envelope interpolation is consumed in LOOK_H3; this free DSP slot precedes pitch vibrato.
                    if(frame_tuning!=16384)begin mul_a<={1'b0,note_inc};mul_b<=$signed({2'd0,frame_tuning});end
                end
                LOOK_AUX:begin h4<={{2{lookup_sample[15]}},lookup_sample}; lookup_phase<=aux_phase; state<=LOOK_AUX2; end
                LOOK_AUX2:begin aux<={{2{lookup_sample[15]}},lookup_sample}; lookup_phase<=aux2_phase; state<=PITCH_MUL; end
                PITCH_MUL:begin
                    aux2<={{2{lookup_sample[15]}},lookup_sample};
                    mul_a<={1'b0,frame_tuning==16384 ? note_inc : mul_product[45:14]};
                    mul_b<=lfo_scaled;state<=PITCH_WAIT;
                end
                PITCH_WAIT:state<=BODY_MUL;
                BODY_MUL:begin
                    phase_step<=adjusted_pitch[31:0];
                    mul_a<={{15{body_wave[17]}},body_wave}; mul_b<={2'd0,body_env[23:8]};
                    state<=BODY_WAIT;
                end
                BODY_WAIT:state<=BRIGHT_MUL;
                BRIGHT_MUL:begin
                    body_product<=mul_product[34:0];
                    mul_a<={{15{bright_wave[17]}},bright_wave}; mul_b<={2'd0,bright_env[23:8]};
                    state<=BRIGHT_WAIT;
                end
                BRIGHT_WAIT:state<=GAIN_MUL;
                GAIN_MUL:begin
                    mul_a<={{17{unscaled_wave[15]}},unscaled_wave}; mul_b<={9'd0,gain};
                    state<=GAIN_WAIT;
                end
                GAIN_WAIT:state<=VOICE_COMMIT;
                VOICE_COMMIT:begin
                    mix<=next_mix;
                    if(voice_active[slot] && !n_active) voice_count<=voice_count-1'b1;
                    voice_active[slot]<=n_active;
                    if(slot==VOICES-1)state<=PUBLISH;
                    else begin slot<=slot+1'b1;state<=VOICE_ACCEPT;end
                end
                PUBLISH:begin
                    sample<=(mix>22'sd32767) ? 16'sh7FFF :
                            (mix< -22'sd32768) ? 16'sh8000 : mix[15:0];
                    state<=IDLE;
                end
                default:state<=INIT;
            endcase
        end
    end
endmodule
