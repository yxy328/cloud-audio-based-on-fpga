`timescale 1ns/1ps
// Case-sensitive ASCII lines, CR/LF/CRLF, <=64 characters excluding EOL.
// Command replies and performance records share UART at complete-line boundaries.
module hc05_keymap #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer BAUD=9600,
    parameter [15:0] DEFAULT_A=98,DEFAULT_D=3906,DEFAULT_S=39321,DEFAULT_R=488,
    parameter integer ENABLE_DEMO_SCORE=0,
    parameter integer ENABLE_LOOKAHEAD=0,
    parameter integer LOOKAHEAD_MS=1500,
    // Legacy demo audio consumes this DDS output. Live AUDITION uses the
    // existing touch voices via guide_keys and needs no extra lookup.
    parameter integer ENABLE_DOWNLOADED_INCREMENT=1,
    parameter integer ENABLE_EVENT_TAKE=0,
    parameter integer ENABLE_FLASH_AUDIO=0,
    parameter integer DEFAULT_TOUCH_MODE16=ENABLE_EVENT_TAKE
) (
    input wire clk, resetn, rx,
    output wire tx,
    input wire keys_ready, song_busy, notes_busy, recording,
    output reg [55:0] note_map,
    input wire [6:0] touch_keys,
    input wire [15:0] scan_keys,
    input wire pressure_mode,
    input wire [15:0] volume_gain, pitch_ratio,
    input wire toggle_play, restart,
    output wire rec_busy,
    output wire downloaded_valid, downloaded_playing, downloaded_gate,
    output reg downloaded_audition,
    output wire [31:0] downloaded_increment,
    output wire [6:0] guide_keys,
    output wire guide_ms_tick, guide_reset, note_spawn,
    output wire [6:0] spawn_keys,
    output wire [15:0] spawn_delay_ms,
    input wire note_ready,
    output reg builtin_play, builtin_stop,
    output reg guitar_pluck,
    output reg [2:0] gesture_timbre,
    output reg gesture_vibrato, gesture_bank,
    output reg sensor_test32,
    output wire [63:0] touch_adsr,
    output wire [129:0] sensor_adsr,
    output reg bend_write,bend_reset,
    output reg [2:0] bend_index,
    output reg [15:0] bend_ratio,
    output reg [15:0] bend_min,bend_max,bend_slew,tuning_ratio,
    output reg [31:0] vibrato_inc,
    output reg [1:0] echo_tap,
    output reg [9:0] vibrato_depth,
    output reg [15:0] vibrato_delay,
    output reg vibrato_update,
    output reg xy_write,
    output reg [1:0] xy_ratio,xy_phase,
    output reg visual_write,
    output reg [1:0] remote_mode,
    input wire [1:0] visual_requested,reference_ratio,reference_phase,
    input wire [111:0] visual_snapshot,
    output reg touch_mode16,panic,serial_active_high,
    output reg [1:0] touch_hold,
    output reg [4:0] poly_limit,
    input wire [4:0] touch_voice_count,
    input wire pedal_clear,take_recording,
    output reg [1:0] effect_mode,
    output reg [3:0] effect_wet,
    output reg [4:0] master_volume,
    output reg [2:0] analog_mode,
    output reg pressure_write,pressure_value,
    output reg [9:0] analog_min,analog_max,
    input wire [9:0] adc_sample,
    input wire adc_timeout,
    input wire audio_rec_busy,audio_rec_ready,audio_rec_overflow,
    input wire audio_rec_valid,
    input wire [3:0] audio_rec_status,audio_rec_error,
    input wire [20:0] audio_rec_stored_samples,
    input wire [15:0] audio_rec_generation,
    input wire [7:0] audio_stream_data,
    input wire audio_stream_valid,audio_stream_last,audio_stream_busy,
    output wire audio_stream_ready,
    output reg audio_rec_prepare,audio_rec_start,audio_rec_stop,audio_rec_abort,audio_rec_send,audio_rec_ack,
    output reg [15:0] audio_rec_ack_sequence,
    output reg [15:0] audio_rec_session,
    output reg [2:0] take_command,
    input wire [7:0] take_flags,
    input wire [3:0] take_error,
    input wire [23:0] take_elapsed,take_duration,
    input wire [10:0] take_count
);
    localparam [55:0] DEFAULT_MAP={8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60};
    localparam COLLECT=0, EXECUTE=1, RESPOND=2, DECIMAL=3, SONG_WAIT=4, DECIMAL_READ=5, ADSR_WAIT=6, DECODE_START=7, DECODE_WAIT=8;
    // BEGIN GENERATED HC05 COMMAND IDS
    localparam [5:0] CMD_UNKNOWN=0;
    localparam [5:0] CMD_PING=6'd1;
    localparam [5:0] CMD_CTRL_QUERY=6'd2;
    localparam [5:0] CMD_SERIAL_QUERY=6'd3;
    localparam [5:0] CMD_SERIAL_SET=6'd4;
    localparam [5:0] CMD_CAL_QUERY=6'd5;
    localparam [5:0] CMD_CAL_SET=6'd6;
    localparam [5:0] CMD_ADC_QUERY=6'd7;
    localparam [5:0] CMD_PANIC=6'd8;
    localparam [5:0] CMD_TOUCH_SET=6'd9;
    localparam [5:0] CMD_EFFECT_SET=6'd10;
    localparam [5:0] CMD_HOLD_SET=6'd11;
    localparam [5:0] CMD_VOLUME_SET=6'd12;
    localparam [5:0] CMD_ANALOG_SET=6'd13;
    localparam [5:0] CMD_PRESSURE_SET=6'd14;
    localparam [5:0] CMD_TAKE_QUERY=6'd15;
    localparam [5:0] CMD_TAKE_REC=6'd16;
    localparam [5:0] CMD_TAKE_DEL=6'd17;
    localparam [5:0] CMD_TAKE_YES=6'd18;
    localparam [5:0] CMD_TAKE_STOP=6'd19;
    localparam [5:0] CMD_TAKE_PLAY=6'd20;
    localparam [5:0] CMD_TAKE_SAVE=6'd21;
    localparam [5:0] CMD_TAKE_NO=6'd22;
    localparam [5:0] CMD_AREC_START=6'd23;
    localparam [5:0] CMD_AREC_STOP=6'd24;
    localparam [5:0] CMD_AREC_ABORT=6'd25;
    localparam [5:0] CMD_AREC_QUERY=6'd26;
    localparam [5:0] CMD_VIS_SET=6'd27;
    localparam [5:0] CMD_VIS_QUERY=6'd28;
    localparam [5:0] CMD_VIZ_QUERY=6'd29;
    localparam [5:0] CMD_XY_SET=6'd30;
    localparam [5:0] CMD_BEND_SET=6'd31;
    localparam [5:0] CMD_BEND_RESET=6'd32;
    localparam [5:0] CMD_ADSR_TOUCH=6'd33;
    localparam [5:0] CMD_ADSR_SENSOR=6'd34;
    localparam [5:0] CMD_ADSR_RESET_TOUCH=6'd35;
    localparam [5:0] CMD_ADSR_RESET_SENSOR=6'd36;
    localparam [5:0] CMD_TEST32=6'd37;
    localparam [5:0] CMD_GUITAR=6'd38;
    localparam [5:0] CMD_TONE_SET=6'd39;
    localparam [5:0] CMD_VIBRATO_SET=6'd40;
    localparam [5:0] CMD_BANK_SET=6'd41;
    localparam [5:0] CMD_MAP_QUERY=6'd42;
    localparam [5:0] CMD_MAP_RESET=6'd43;
    localparam [5:0] CMD_MAP_SET=6'd44;
    localparam [5:0] CMD_SONG_BEGIN=6'd45;
    localparam [5:0] CMD_SONG_NOTE=6'd46;
    localparam [5:0] CMD_SONG_CHORD=6'd47;
    localparam [5:0] CMD_SONG_END=6'd48;
    localparam [5:0] CMD_PLAY=6'd49;
    localparam [5:0] CMD_AUDITION=6'd50;
    localparam [5:0] CMD_STOP=6'd51;
    localparam [5:0] CMD_REC_START=6'd52;
    localparam [5:0] CMD_REC_STOP=6'd53;
    localparam [5:0] CMD_AREC_PREP=6'd54;
    localparam [5:0] CMD_AREC_SEND=6'd55;
    localparam [5:0] CMD_AREC_ACK=6'd56;
    localparam [5:0] CMD_POLY_SET=6'd57;
    localparam [5:0] CMD_CTRL2_QUERY=6'd58;
    localparam [5:0] CMD_PITCH_SET=6'd59;
    localparam [5:0] CMD_VIB_SET=6'd60;
    localparam [5:0] CMD_EFFECT2_SET=6'd62;
    localparam [5:0] CMD_KLIVE_ON=6'd61;
    localparam [5:0] CMD_KLIVE_OFF=6'd63;
    // END GENERATED HC05 COMMAND IDS
    localparam NO_ERROR=0, LENGTH_ERROR=1, CHAR_ERROR=2, UART_ERROR=3;
    (* syn_encoding="onehot" *) reg [3:0] state;
    reg [1:0] line_error;
    reg [31:0] line; // Only the last four argument bytes need parallel access.
    reg [6:0] line_length, parse_length, position;
    reg [111:0] reply;
    reg [4:0] reply_format;
    reg [5:0] reply_remaining;
    wire visual_reply=reply_format==18;
    reg reply_char_ready;
    (* syn_romstyle="block_rom" *) reg [7:0] reply_rom [0:1023];
    reg [7:0] reply_template;
    initial $readmemh("src/hc05_reply.hex",reply_rom);
    always @(posedge clk)reply_template<=reply_rom[{reply_format,reply_remaining[4:0]}];
    wire [7:0] received;
    wire [7:0] reply_byte;
    wire received_valid, rx_fault, tx_ready;
    reg log_owned;
    wire [7:0] log_data;
    wire log_valid, log_last, log_ready;
    reg stream_owned;
    wire select_stream=ENABLE_FLASH_AUDIO && (stream_owned || (state!=RESPOND && audio_stream_valid));
    wire block_log=ENABLE_FLASH_AUDIO && audio_stream_busy;
    wire select_log=!select_stream && !block_log && (log_owned || (state!=RESPOND && log_valid));
    reg live_owned;
    reg klive_enable;
    wire [7:0] live_data;
    wire live_valid, live_last, live_ready;
    wire select_live=!select_stream && !select_log && (live_owned || (state!=RESPOND && live_valid));
    wire [7:0] requested_note={4'd0,line[11:8]}*8'd10+{4'd0,line[3:0]};
    wire download_busy;
    wire edit_allowed=keys_ready && !song_busy && !download_busy && !notes_busy && !recording && !rec_busy;
    reg song_request, rec_start, rec_stop;
    reg audition_pending;
    reg [2:0] song_operation;
    reg [15:0] song_arg0, song_arg1, song_arg2;
    wire song_done;
    wire [2:0] song_error;
    wire [7:0] download_note;
    reg [2:0] field_index, field_count;
    reg [15:0] accumulator, value0, value1, value2;
    reg have_digit;
    reg [1:0] performance_parse;
    wire [15:0] performance3=(field_index==3 && have_digit) ? accumulator : performance_parse==1 ? tuning_ratio : vibrato_delay;
    wire [15:0] pitch0=(field_index==0 && have_digit) ? accumulator : value0;
    wire [15:0] pitch1=(field_index==1 && have_digit) ? accumulator : value1;
    wire [15:0] pitch2=(field_index==2 && have_digit) ? accumulator : value2;
    (* syn_ramstyle="block_ram" *) reg [7:0] command_bytes [0:63];
    reg [7:0] ch;
    reg adsr_parse,adsr_target,adsr_request,adsr_restore;
    reg bend_parse;
    reg [3:0] control_parse;
    reg [15:0] adsr_a,adsr_d,adsr_s,adsr_r;
    wire adsr_done;
    wire [5:0] decoded_command,decode_position;
    wire decode_done;
    wire decoding=state==DECODE_START || state==DECODE_WAIT;
    hc05_command_decode u_command_decode(
        .clk(clk),.resetn(resetn && !rx_fault),
        .start(state==DECODE_START && line_error==NO_ERROR && !rx_fault),
        .line_length(line_length),.character(ch),.position(decode_position),
        .done(decode_done),.command(decoded_command));
    always @(posedge clk) begin
        ch<=command_bytes[decoding ? decode_position : position[5:0]];
        if(resetn && state==COLLECT && received_valid && line_error==NO_ERROR &&
           line_length<64 && received>=32 && received<=126)
            command_bytes[line_length[5:0]]<=received;
    end
    adsr_config #(.DEFAULT_A(DEFAULT_A),.DEFAULT_D(DEFAULT_D),.DEFAULT_S(DEFAULT_S),.DEFAULT_R(DEFAULT_R)) u_adsr_config (
        .clk(clk),.resetn(resetn),.request(adsr_request),.restore(adsr_restore),.profile(adsr_target),
        .attack_ms(adsr_a),.decay_ms(adsr_d),.sustain_percent(adsr_s),.release_ms(adsr_r),
        .done(adsr_done),.touch_config(touch_adsr),.sensor_config(sensor_adsr));
    assign log_ready=select_log && tx_ready;
    assign audio_stream_ready=select_stream && tx_ready;
    assign live_ready=select_live && tx_ready;
    uart_8n1 #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_uart (
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),
        .rx_data(received),.rx_valid(received_valid),.rx_ready(state==COLLECT),
        .rx_fault(rx_fault),.tx_data(select_stream ? audio_stream_data : select_log ? log_data : select_live ? live_data : reply_byte),
        .tx_valid(select_stream ? audio_stream_valid : select_log ? log_valid : select_live ? live_valid : state==RESPOND && reply_char_ready),.tx_ready(tx_ready)
    );
    key_live_stream u_live (
        .clk(clk),.resetn(resetn),.enable(klive_enable),.scan_keys(scan_keys),
        .tx_data(live_data),.tx_valid(live_valid),.tx_last(live_last),.tx_ready(live_ready)
    );
    downloadable_song #(.CLK_HZ(CLK_HZ),.ENABLE_LOOKAHEAD(ENABLE_LOOKAHEAD),
        .LOOKAHEAD_MS(LOOKAHEAD_MS)) u_download (
        .clk(clk),.resetn(resetn),.request(song_request),.operation(song_operation),
        .arg0(song_arg0),.arg1(song_arg1),.arg2(song_arg2),.edit_allowed(edit_allowed),
        .note_map(note_map),.toggle_play(toggle_play),.restart(restart),
        .done(song_done),.error(song_error),.valid(downloaded_valid),.playing(downloaded_playing),
        .gate(downloaded_gate),.current_note(download_note),.guide_keys(guide_keys),
        .ms_tick(guide_ms_tick),.guide_reset(guide_reset),.note_spawn(note_spawn),
        .spawn_keys(spawn_keys),.spawn_delay_ms(spawn_delay_ms),.note_ready(note_ready),
        .current_mask(),.busy(download_busy)
    );
    generate
        if(ENABLE_DOWNLOADED_INCREMENT) begin: download_pitch_enabled
            wire [223:0] download_steps;
            midi_note_lut u_download_lut (
                .clk(clk),.resetn(resetn),.note_map({7{download_note}}),.phase_increments(download_steps)
            );
            assign downloaded_increment=download_steps[31:0];
        end else begin: download_pitch_disabled
            assign downloaded_increment=32'd0;
        end
    endgenerate
    generate if(!ENABLE_EVENT_TAKE && !ENABLE_FLASH_AUDIO)begin: legacy_log
    performance_logger #(.CLK_HZ(CLK_HZ)) u_logger (
        .clk(clk),.resetn(resetn),.start(rec_start),.stop(rec_stop),.note_map(note_map),
        .touch_keys(touch_keys),.pressure_mode(pressure_mode),.volume_gain(volume_gain),.pitch_ratio(pitch_ratio),
        .recording(rec_busy),.tx_data(log_data),.tx_valid(log_valid),.tx_last(log_last),.tx_ready(log_ready),.dropped()
    );
    end else begin: event_log_disabled
        assign rec_busy=1'b0;assign log_data=0;assign log_valid=0;assign log_last=0;
    end endgenerate
    function [7:0] hex_char;
        input [3:0] n;
        begin hex_char=n<10 ? "0"+n : "A"+n-10;end
    endfunction
    // A single ROM streams punctuation and static text. Only binary values
    // are snapshotted, and every dynamic digit shares one hex encoder.
    assign reply_byte=reply_template==8'hff ? hex_char(reply[111:108]) : reply_template;
    function [7:0] tens;
        input [7:0] note;
        begin tens=(note<70) ? "6" : "7"; end
    endfunction
    function [7:0] ones;
        input [7:0] note;
        begin ones=8'd48+((note<70) ? note-8'd60 : note-8'd70); end
    endfunction
    task respond;
        input [4:0] format;
        input [5:0] length;
        begin reply_format<=format;reply_remaining<=length;reply_char_ready<=0;state<=RESPOND;end
    endtask
    task result;
        input [2:0] error_code;
        begin
            if(ENABLE_FLASH_AUDIO && audio_stream_busy)state<=COLLECT;
            else case(error_code)
                0: respond(5'd0,6'd4);
                1: respond(5'd1,6'd10);
                2: respond(5'd2,6'd11);
                3: respond(5'd3,6'd11);
                4: respond(5'd4,6'd13);
                5: respond(5'd5,6'd9);
                default: respond(5'd6,6'd9);
            endcase
        end
    endtask
    task parse_numbers;
        input [6:0] first_position;
        input [2:0] fields;
        begin
            parse_length<=line_length; position<=first_position; field_count<=fields;
            field_index<=0; accumulator<=0; value0<=0; value1<=0; value2<=0; have_digit<=0;
            state<=DECIMAL_READ;
        end
    endtask
    always @(posedge clk) begin
        if(!resetn) begin
            note_map<=DEFAULT_MAP; state<=COLLECT; line_error<=NO_ERROR;
            line<=0; line_length<=0; reply<=0; reply_remaining<=0;reply_format<=0;reply_char_ready<=0;log_owned<=0;
            live_owned<=0; klive_enable<=0;
            song_request<=0; rec_start<=0; rec_stop<=0;
            downloaded_audition<=0; audition_pending<=0;
            song_operation<=0; song_arg0<=0; song_arg1<=0; song_arg2<=0;
            builtin_play<=0; builtin_stop<=0;
            guitar_pluck<=0; gesture_timbre<=0; gesture_vibrato<=0; gesture_bank<=0;
            sensor_test32<=0;
            audio_rec_prepare<=0;audio_rec_start<=0;audio_rec_stop<=0;audio_rec_abort<=0;audio_rec_send<=0;audio_rec_ack<=0;
            audio_rec_ack_sequence<=0;audio_rec_session<=0;take_command<=0;stream_owned<=0;
            touch_mode16<=DEFAULT_TOUCH_MODE16!=0;serial_active_high<=0;touch_hold<=0;poly_limit<=16;panic<=0;effect_mode<=0;effect_wet<=4;
            master_volume<=16;analog_mode<=0;analog_min<=0;analog_max<=1023;pressure_write<=0;pressure_value<=0;control_parse<=0;
            xy_write<=0;xy_ratio<=2;xy_phase<=0;
            visual_write<=0;remote_mode<=0;
            bend_parse<=0;bend_write<=0;bend_reset<=0;bend_index<=0;bend_ratio<=16384;
            performance_parse<=0;bend_min<=8192;bend_max<=32768;bend_slew<=4096;tuning_ratio<=16384;
            vibrato_inc<=527766;vibrato_depth<=256;vibrato_delay<=0;vibrato_update<=0;
            echo_tap<=0;
            adsr_parse<=0;adsr_target<=0;adsr_request<=0;adsr_restore<=0;
            adsr_a<=0;adsr_d<=0;adsr_s<=0;adsr_r<=0;value2<=0;
            field_index<=0; field_count<=0; accumulator<=0; value0<=0; value1<=0;
            have_digit<=0; parse_length<=0; position<=0;
        end else begin
            song_request<=0; rec_start<=0; rec_stop<=0; builtin_play<=0; builtin_stop<=0;
            guitar_pluck<=0;panic<=0;pressure_write<=0;
            sensor_test32<=0;adsr_request<=0;
            bend_write<=0;bend_reset<=0;vibrato_update<=0;
            xy_write<=0;
            visual_write<=0;
            audio_rec_prepare<=0;audio_rec_start<=0;audio_rec_stop<=0;audio_rec_abort<=0;audio_rec_send<=0;audio_rec_ack<=0;
            take_command<=0;
            // Audition is opt-in for one UART start only. Physical controls
            // always return to silent guidance; ending a score disarms it.
            if(!downloaded_playing) downloaded_audition<=0;
            if(select_log && log_valid && tx_ready) log_owned<=!log_last;
            if(select_stream && audio_stream_valid && tx_ready)stream_owned<=!audio_stream_last;
            if(select_live && live_valid && tx_ready) live_owned<=!live_last;
            if(rx_fault) begin
                line_error<=UART_ERROR;
                if(state==COLLECT || state==EXECUTE || decoding) begin line<=0; line_length<=0; state<=COLLECT; end
            end
            if(state==RESPOND) begin
                if(!reply_char_ready)reply_char_ready<=1;
                else if(!select_log && !select_stream && !select_live && tx_ready) begin
                    if(reply_template==8'hff)reply<={reply[107:0],4'd0};
                    reply_char_ready<=0;
                    reply_remaining<=reply_remaining-1'b1;
                    if(reply_remaining==1)state<=COLLECT;
                end
            end else if(!rx_fault || (state!=COLLECT && state!=EXECUTE && !decoding)) begin
                case(state)
                    COLLECT: if(received_valid) begin
                        if(received==13 || received==10) begin
                            if(line_length!=0 || line_error!=NO_ERROR) state<=DECODE_START;
                        end else if(line_error==NO_ERROR) begin
                            if(line_length==64) line_error<=LENGTH_ERROR;
                            else if(received<32 || received>126) line_error<=CHAR_ERROR;
                            else begin
                                line<=line_length==0 ? {24'd0,received} : {line[23:0],received};
                                line_length<=line_length+1'b1;
                            end
                        end
                    end
                    DECODE_START:state<=line_error==NO_ERROR ? DECODE_WAIT : EXECUTE;
                    DECODE_WAIT:if(decode_done)state<=EXECUTE;
                    EXECUTE: begin
                        line_length<=0; line_error<=NO_ERROR;adsr_parse<=0;adsr_restore<=0;bend_parse<=0;control_parse<=0;performance_parse<=0;
                        // Download owns the binary link; do not inject text on noise or unrelated commands.
                        if(ENABLE_FLASH_AUDIO && audio_stream_busy && (line_error!=NO_ERROR ||
                            (decoded_command!=CMD_AREC_ACK && decoded_command!=CMD_AREC_ABORT)))state<=COLLECT;
                        else if(line_error==UART_ERROR) respond(5'd7,6'd10);
                        else if(line_error==LENGTH_ERROR) respond(5'd8,6'd12);
                        else if(line_error==CHAR_ERROR) respond(5'd6,6'd9);
                        else if(decoded_command==CMD_PING) respond(5'd9,6'd6);
                        else if(decoded_command==CMD_EFFECT2_SET)begin
                            if(line_length==9 && line[7:0]=="?")begin
                                reply<={2'd0,echo_tap,108'd0};respond(5'd29,6'd11);
                            end else begin
                                performance_parse<=3;parse_numbers(8,1);
                                value0<={14'd0,echo_tap};
                            end
                        end
                        else if(decoded_command==CMD_VIB_SET)begin
                            if(line_length==5 && line[7:0]=="?")begin
                                reply<={vibrato_inc,2'd0,vibrato_depth,vibrato_delay,52'd0};respond(5'd28,6'd24);
                            end else begin
                                performance_parse<=2;parse_numbers(4,4);
                                value0<=vibrato_inc[31:16];value1<=vibrato_inc[15:0];value2<={6'd0,vibrato_depth};
                            end
                        end
                        else if(decoded_command==CMD_PITCH_SET) begin
                            if(line_length==7 && line[7:0]=="?")begin
                                reply<={bend_min,bend_max,bend_slew,tuning_ratio,48'd0};respond(5'd27,6'd27);
                            end else begin
                                performance_parse<=1;parse_numbers(6,4);
                                value0<=bend_min;value1<=bend_max;value2<=bend_slew;
                            end
                        end
                        else if(decoded_command==CMD_CTRL_QUERY || decoded_command==CMD_CTRL2_QUERY)begin
                            reply<={{3'd0,touch_mode16},{2'd0,effect_mode},effect_wet,
                                (decoded_command==CMD_CTRL_QUERY ? {3'd0,touch_hold!=0} : {2'd0,touch_hold}),
                                {1'd0,analog_mode},(master_volume>=10 ? 4'd1 : 4'd0),
                                (master_volume>=10 ? master_volume[3:0]-4'd10 : master_volume[3:0]),{3'd0,pressure_mode},
                                (poly_limit>=10 ? 4'd1 : 4'd0),(poly_limit>=10 ? poly_limit[3:0]-4'd10 : poly_limit[3:0]),
                                (touch_voice_count>=10 ? 4'd1 : 4'd0),(touch_voice_count>=10 ? touch_voice_count[3:0]-4'd10 : touch_voice_count[3:0]),64'd0};
                            respond(decoded_command==CMD_CTRL_QUERY ? 5'd10 : 5'd26,decoded_command==CMD_CTRL_QUERY ? 6'd21 : 6'd28);
                        end else if(decoded_command==CMD_SERIAL_QUERY) begin
                            reply<={{3'd0,serial_active_high},108'd0};respond(5'd11,6'd10);
                        end else if(decoded_command==CMD_SERIAL_SET) begin
                            control_parse<=8;parse_numbers(7,1);
                        end else if(decoded_command==CMD_CAL_QUERY) begin
                            reply<={2'd0,analog_min,2'd0,analog_max,88'd0};respond(5'd12,6'd13);
                        end else if(decoded_command==CMD_CAL_SET) begin
                            control_parse<=7;parse_numbers(4,2);
                        end else if(decoded_command==CMD_ADC_QUERY) begin
                            reply<={2'd0,adc_sample,3'd0,adc_timeout,96'd0};respond(5'd13,6'd11);
                        end else if(decoded_command==CMD_PANIC) begin
                            panic<=1;touch_hold<=0;downloaded_audition<=0;audition_pending<=0;
                            builtin_stop<=1;song_request<=1;song_operation<=5;state<=SONG_WAIT;
                        end else if(decoded_command==CMD_TOUCH_SET) begin
                            control_parse<=1;parse_numbers(6,1);
                        end else if(decoded_command==CMD_EFFECT_SET) begin
                            control_parse<=2;parse_numbers(7,2);
                        end else if(decoded_command==CMD_HOLD_SET) begin
                            if(line_length==6 && line[7:0]=="?")begin
                                reply<={2'd0,touch_hold,108'd0};respond(5'd24,6'd8);
                            end else begin control_parse<=3;parse_numbers(5,1);end
                        end else if(decoded_command==CMD_POLY_SET)begin
                            if(line_length==6 && line[7:0]=="?")begin
                                reply<={(poly_limit>=10 ? 4'd1 : 4'd0),
                                    (poly_limit>=10 ? poly_limit[3:0]-4'd10 : poly_limit[3:0]),104'd0};respond(5'd25,6'd9);
                            end else begin control_parse<=12;parse_numbers(5,1);end
                        end else if(decoded_command==CMD_VOLUME_SET) begin
                            control_parse<=4;parse_numbers(7,1);
                        end else if(decoded_command==CMD_ANALOG_SET) begin
                            control_parse<=5;parse_numbers(7,1);
                        end else if(decoded_command==CMD_PRESSURE_SET) begin
                            control_parse<=6;parse_numbers(9,1);
                        end
                        else if(decoded_command==CMD_TAKE_QUERY && ENABLE_EVENT_TAKE)begin
                            reply<={take_flags,take_error,take_elapsed,1'b0,take_count,take_duration,40'd0};respond(5'd14,6'd29);
                        end else if(ENABLE_EVENT_TAKE &&
                            ((line_length==8 && (decoded_command==CMD_TAKE_REC || decoded_command==CMD_TAKE_DEL || decoded_command==CMD_TAKE_YES)) ||
                             (line_length==9 && (decoded_command==CMD_TAKE_STOP || decoded_command==CMD_TAKE_PLAY || decoded_command==CMD_TAKE_SAVE)) ||
                             (decoded_command==CMD_TAKE_NO)))begin
                            if(decoded_command==CMD_TAKE_STOP)begin take_command<=2;result(0);end
                            else if((decoded_command==CMD_TAKE_REC || (decoded_command==CMD_TAKE_YES && take_flags[7:6]==1)) &&
                                    (touch_hold==2 || poly_limit!=16))result(1);
                            else if(take_flags[5] || take_flags[1:0]!=0 || (ENABLE_FLASH_AUDIO && audio_rec_busy))result(1);
                            else begin
                                if(decoded_command==CMD_TAKE_REC)take_command<=1;
                                else if(line_length==9)take_command<=decoded_command==CMD_TAKE_SAVE ? 3'd7 : 3'd3;
                                else if(decoded_command==CMD_TAKE_DEL)take_command<=4;
                                else if(line_length==8)take_command<=5;
                                else take_command<=6;
                                result(0);
                            end
                        end
                        else if(decoded_command==CMD_AREC_START)begin
                            control_parse<=9;parse_numbers(11,1);
                        end else if(decoded_command==CMD_AREC_STOP)begin
                            audio_rec_stop<=1;result(0);
                        end else if(decoded_command==CMD_AREC_ABORT)begin
                            audio_rec_abort<=1;if(ENABLE_FLASH_AUDIO && audio_stream_busy)state<=COLLECT;else result(0);
                        end else if(decoded_command==CMD_AREC_QUERY)begin
                            if(ENABLE_FLASH_AUDIO)begin
                                reply<={{3'd0,audio_rec_busy},{3'd0,audio_rec_ready},{3'd0,audio_rec_overflow},
                                    {3'd0,audio_rec_valid},audio_rec_status,audio_rec_error,audio_rec_generation,
                                    3'd0,audio_rec_stored_samples,48'd0};respond(5'd15,6'd30);
                            end else begin
                                reply<={{3'd0,audio_rec_busy},{3'd0,audio_rec_ready},{3'd0,audio_rec_overflow},100'd0};respond(5'd16,6'd12);
                            end
                        end
                        else if(decoded_command==CMD_AREC_PREP)begin
                            if(!ENABLE_FLASH_AUDIO || audio_rec_busy || (ENABLE_EVENT_TAKE && take_flags[5]))result(ENABLE_FLASH_AUDIO ? 1 : 3);
                            else begin audio_rec_prepare<=1;result(0);end
                        end else if(decoded_command==CMD_AREC_SEND)begin
                            control_parse<=10;parse_numbers(10,1);
                        end else if(decoded_command==CMD_AREC_ACK)begin
                            control_parse<=11;parse_numbers(9,1);
                        end
                        else if(decoded_command==CMD_VIS_SET) begin
                            if(line[7:0]>="0" && line[7:0]<="3") begin
                                remote_mode<=line[1:0];visual_write<=1;result(0);
                            end else result(2);
                        end else if(decoded_command==CMD_VIS_QUERY) begin
                            reply<={{2'd0,visual_requested},{2'd0,visual_snapshot[103:102]},
                                {2'd0,reference_ratio},{2'd0,reference_phase},{2'd0,visual_snapshot[101:100]},
                                {2'd0,visual_snapshot[99:98]},visual_snapshot[107:104],84'd0};respond(5'd17,6'd19);
                        end else if(decoded_command==CMD_VIZ_QUERY) begin
                            // Exactly 32 UART bytes, captured atomically into the existing reply register.
                            reply<=visual_snapshot;respond(5'd18,6'd32);
                        end
                        else if(decoded_command==CMD_XY_SET && line[15:8]==",") begin
                            if(line[23:16]>="0" && line[23:16]<="3" && line[7:0]>="0" && line[7:0]<="3") begin
                                xy_ratio<=line[17:16];xy_phase<=line[1:0];xy_write<=1;result(0);
                            end else result(2);
                        end
                        else if(decoded_command==CMD_BEND_SET) begin
                            bend_parse<=1;parse_numbers(5,2);
                        end else if(decoded_command==CMD_BEND_RESET) begin
                            bend_reset<=1;result(0);
                        end
                        else if(decoded_command==CMD_ADSR_TOUCH) begin
                            adsr_parse<=1;adsr_target<=0;parse_numbers(11,4);
                        end else if(decoded_command==CMD_ADSR_SENSOR) begin
                            adsr_parse<=1;adsr_target<=1;parse_numbers(12,4);
                        end else if((decoded_command==CMD_ADSR_RESET_TOUCH || decoded_command==CMD_ADSR_RESET_SENSOR)) begin
                            adsr_target<=line_length==17;adsr_request<=1;adsr_restore<=1;state<=ADSR_WAIT;
                        end else if(decoded_command==CMD_TEST32) begin
                            sensor_test32<=1; gesture_vibrato<=0; result(0);
                        end else if(decoded_command==CMD_GUITAR) begin
                            guitar_pluck<=1; result(0);
                        end else if(decoded_command==CMD_TONE_SET) begin
                            if(line[7:0]<"0" || line[7:0]>"9") result(7);
                            else if(line[7:0]>"7") result(2);
                            else begin gesture_timbre<=line[2:0]; result(0); end
                        end else if(decoded_command==CMD_VIBRATO_SET) begin
                            if(line[7:0]<"0" || line[7:0]>"9") result(7);
                            else if(line[7:0]>"1") result(2);
                            else begin gesture_vibrato<=line[0]; result(0); end
                        end else if(decoded_command==CMD_BANK_SET) begin
                            if(line[7:0]<"0" || line[7:0]>"9") result(7);
                            else if(line[7:0]>"1") result(2);
                            else begin gesture_bank<=line[0]; result(0); end
                        end
                        else if(decoded_command==CMD_MAP_QUERY) begin
                            reply<={(note_map[7:0]<70 ? 4'd6 : 4'd7),(note_map[7:0]<70 ? note_map[3:0]-4'd12 : note_map[3:0]-4'd6),(note_map[15:8]<70 ? 4'd6 : 4'd7),(note_map[15:8]<70 ? note_map[11:8]-4'd12 : note_map[11:8]-4'd6),(note_map[23:16]<70 ? 4'd6 : 4'd7),(note_map[23:16]<70 ? note_map[19:16]-4'd12 : note_map[19:16]-4'd6),(note_map[31:24]<70 ? 4'd6 : 4'd7),(note_map[31:24]<70 ? note_map[27:24]-4'd12 : note_map[27:24]-4'd6),(note_map[39:32]<70 ? 4'd6 : 4'd7),(note_map[39:32]<70 ? note_map[35:32]-4'd12 : note_map[35:32]-4'd6),(note_map[47:40]<70 ? 4'd6 : 4'd7),(note_map[47:40]<70 ? note_map[43:40]-4'd12 : note_map[43:40]-4'd6),(note_map[55:48]<70 ? 4'd6 : 4'd7),(note_map[55:48]<70 ? note_map[51:48]-4'd12 : note_map[51:48]-4'd6),56'd0};respond(5'd19,6'd26);
                        end else if(decoded_command==CMD_MAP_RESET) begin
                            if(!edit_allowed) result(1);
                            else begin note_map<=DEFAULT_MAP; respond(5'd20,6'd14); end
                        end else if(decoded_command==CMD_MAP_SET && line[23:16]==",") begin
                            if(line[31:24]<"1" || line[31:24]>"7") respond(5'd21,6'd9);
                            else if(line[15:8]<"0" || line[15:8]>"9" || line[7:0]<"0" || line[7:0]>"9") result(7);
                            else if(requested_note<60 || requested_note>72) respond(5'd22,6'd10);
                            else if(!edit_allowed) result(1);
                            else begin
                                note_map[(line[26:24]-3'd1)*8 +: 8]<=requested_note;
                                reply<={line[27:24],line[11:8],line[3:0],100'd0};respond(5'd23,6'd13);
                            end
                        end else if(decoded_command==CMD_SONG_BEGIN) begin
                            song_operation<=1; parse_numbers(11,1);
                        end else if(decoded_command==CMD_SONG_NOTE) begin
                            song_operation<=2; parse_numbers(10,3);
                        end else if(decoded_command==CMD_SONG_CHORD) begin
                            song_operation<=6; parse_numbers(11,3);
                        end else if(decoded_command==CMD_SONG_END) begin
                            song_request<=1; song_operation<=3; state<=SONG_WAIT;
                        end else if(decoded_command==CMD_PLAY) begin
                            if(!keys_ready) result(1);
                            else begin
                                 downloaded_audition<=0; audition_pending<=0;
                                if(downloaded_valid) begin song_request<=1; song_operation<=4; state<=SONG_WAIT; end
                                else if(ENABLE_DEMO_SCORE) begin builtin_play<=1; result(0); end
                                else result(3);
                            end
                         end else if(decoded_command==CMD_AUDITION) begin
                             if(!keys_ready || rec_busy || recording) result(1);
                             else if(!downloaded_valid) result(3);
                             else begin
                                 downloaded_audition<=0; audition_pending<=1;
                                 song_request<=1; song_operation<=4; state<=SONG_WAIT;
                             end
                         end else if(decoded_command==CMD_STOP) begin
                             downloaded_audition<=0; audition_pending<=0;
                            builtin_stop<=1; song_request<=1; song_operation<=5;
                            state<=SONG_WAIT;
                        end else if(decoded_command==CMD_REC_START) begin
                            if(ENABLE_EVENT_TAKE || ENABLE_FLASH_AUDIO)result(3);
                            else if(!keys_ready || rec_busy || recording || touch_mode16 || touch_hold || analog_mode!=0) result(1);
                            else begin rec_start<=1; result(0); end
                        end else if(decoded_command==CMD_REC_STOP) begin rec_stop<=1; result(0); end
                        else if(decoded_command==CMD_KLIVE_ON) begin klive_enable<=1; result(0); end
                        else if(decoded_command==CMD_KLIVE_OFF) begin klive_enable<=0; result(0); end
                        else result(7);
                    end
                    DECIMAL_READ:state<=DECIMAL;
                    ADSR_WAIT:if(adsr_done && !adsr_request) result(0);
                    DECIMAL: begin
                        if(position==parse_length) begin
                            if(performance_parse==1)begin
                                if(pitch0<8192 || pitch0>15918 || pitch1<16864 || pitch1>32768 || pitch2==0 || performance3<7727 || performance3>34704)result(2);
                                else if(analog_mode==2 && performance3!=16384)result(3);
                                else if(rec_busy || recording || take_recording ||
                                    ((!edit_allowed) && (pitch0!=bend_min || pitch1!=bend_max)))result(1);
                                else begin bend_min<=pitch0;bend_max<=pitch1;bend_slew<=pitch2;tuning_ratio<=performance3;result(0);end
                            end else if(performance_parse==2)begin
                                if({pitch0,pitch1}<32'd263883 || {pitch0,pitch1}>32'd703687 || pitch2>1023 || performance3>39063)result(2);
                                else if(rec_busy || recording || take_recording)result(1);
                                else begin
                                    vibrato_inc<={pitch0,pitch1};vibrato_depth<=pitch2[9:0];
                                    vibrato_delay<=performance3;vibrato_update<=1;result(0);
                                end
                            end else if(performance_parse==3)begin
                                if(pitch0>3)result(2);
                                else if(rec_busy || recording || take_recording)result(1);
                                else begin echo_tap<=pitch0[1:0];result(0);end
                            end else if(!have_digit || field_count==0 || field_index!=field_count-1) result(7);
                            else if(control_parse!=0) begin
                                case(control_parse)
                                    1:if(accumulator!=8 && accumulator!=16)result(2);
                                      else if(!edit_allowed || touch_hold)result(1);
                                      else begin touch_mode16<=accumulator==16;result(0);end
                                    2:if(value0>2 || accumulator>8)result(2);
                                      else begin effect_mode<=value0[1:0];effect_wet<=accumulator[3:0];result(0);end
                                    3:if(accumulator>2)result(2);
                                      else if(rec_busy || recording || (accumulator==2 && take_recording))result(1);
                                      else begin touch_hold<=accumulator[1:0];result(0);end
                                    4:if(accumulator>16)result(2);
                                      else begin master_volume<=accumulator[4:0];result(0);end
                                    5:if(accumulator>4)result(2);
                                      else if(rec_busy || recording)result(1);
                                      else if(accumulator==2 && tuning_ratio!=16384)result(3);
                                      else begin analog_mode<=accumulator[2:0];result(0);end
                                    6:if(accumulator>1)result(2);
                                      else begin pressure_write<=1;pressure_value<=accumulator[0];result(0);end
                                    7:if(value0>1023 || accumulator>1023 || accumulator<=value0 || accumulator-value0<32)result(2);
                                      else if(rec_busy || recording)result(1);
                                      else begin analog_min<=value0[9:0];analog_max<=accumulator[9:0];result(0);end
                                    8:if(accumulator>1)result(2);
                                      else if(!edit_allowed || touch_hold)result(1);
                                      else begin serial_active_high<=accumulator[0];result(0);end
                                    9:if(audio_rec_busy || (ENABLE_FLASH_AUDIO && ENABLE_EVENT_TAKE && take_flags[5]))result(1);
                                      else if(!audio_rec_ready)result(3);
                                      else begin audio_rec_session<=accumulator;audio_rec_start<=1;result(0);end
                                    10:if(!ENABLE_FLASH_AUDIO || audio_rec_busy || (ENABLE_EVENT_TAKE && take_flags[5]))result(ENABLE_FLASH_AUDIO ? 1 : 3);
                                      else if(!audio_rec_valid)result(4);
                                      else begin audio_rec_session<=accumulator;audio_rec_send<=1;result(0);end
                                    11:begin audio_rec_ack_sequence<=accumulator;audio_rec_ack<=1;state<=COLLECT;end
                                    12:if(accumulator!=1 && accumulator!=2 && accumulator!=4 && accumulator!=8 && accumulator!=16)result(2);
                                       else if(rec_busy || recording || take_recording)result(1);
                                       else begin poly_limit<=accumulator[4:0];result(0);end
                                    default:result(7);
                                endcase
                            end else if(bend_parse) begin
                                if(value0<1 || value0>7 || accumulator<bend_min || accumulator>bend_max) result(2);
                                else begin
                                    bend_index<=value0[2:0]-1'b1;bend_ratio<=accumulator;bend_write<=1;result(0);
                                end
                            end else if(adsr_parse) begin
                                if(value0>1000 || value1>1000 || value2>100 || accumulator>1000) result(2);
                                else begin
                                    adsr_a<=value0;adsr_d<=value1;adsr_s<=value2;adsr_r<=accumulator;
                                    adsr_request<=1;state<=ADSR_WAIT;
                                end
                            end else begin
                                song_arg0<=(field_count==1) ? accumulator : value0;
                                song_arg1<=value1; song_arg2<=accumulator;
                                song_request<=1; state<=SONG_WAIT;
                            end
                        end else if(ch==",") begin
                            if(!have_digit && performance_parse==0) result(7);
                            else if(field_index>=field_count-1) result(7);
                            else begin
                                if(have_digit)begin
                                    if(field_index==0) value0<=accumulator; else if(field_index==1) value1<=accumulator; else value2<=accumulator;
                                end
                                accumulator<=0; have_digit<=0; field_index<=field_index+1'b1; position<=position+1'b1;state<=DECIMAL_READ;
                            end
                        end else if(ch<"0" || ch>"9") result(7);
                        else if(accumulator>6553 || (accumulator==6553 && ch>"5")) result(2);
                        else begin accumulator<=accumulator*16'd10+{12'd0,ch[3:0]}; have_digit<=1; position<=position+1'b1;state<=DECIMAL_READ; end
                    end
                    // Ignore a hardware-control completion on the cycle in
                    // which this new UART request is only being accepted.
                    SONG_WAIT: if(song_done && !song_request) begin
                        if(song_operation==4) begin
                            downloaded_audition<=song_error==0 && audition_pending &&
                                downloaded_playing && !toggle_play && !restart;
                            audition_pending<=0;
                        end
                        result(song_error);
                    end
                    default: state<=COLLECT;
                endcase
            end
            // A physical action also cancels a UART start still validating.
            // Give it priority over the command decoder on the same cycle.
            if(toggle_play || restart) begin
                downloaded_audition<=0; audition_pending<=0;
            end
            if(pedal_clear && touch_hold==2)touch_hold<=0;
        end
    end
endmodule
