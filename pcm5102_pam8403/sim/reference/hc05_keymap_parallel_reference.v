`timescale 1ns/1ps
// Case-sensitive ASCII lines, CR/LF/CRLF, <=64 characters excluding EOL.
// Command replies and performance records share UART at complete-line boundaries.
module hc05_keymap_parallel_reference #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer BAUD=9600,
    parameter [15:0] DEFAULT_A=98,DEFAULT_D=3906,DEFAULT_S=39321,DEFAULT_R=488,
    parameter integer ENABLE_DEMO_SCORE=0,
    parameter integer ENABLE_LOOKAHEAD=0,
    parameter integer LOOKAHEAD_MS=1500,
    // Legacy demo audio consumes this DDS output. Live AUDITION uses the
    // existing touch voices via guide_keys and needs no extra lookup.
    parameter integer ENABLE_DOWNLOADED_INCREMENT=1,
    parameter integer ENABLE_EVENT_TAKE=0
) (
    input wire clk, resetn, rx,
    output wire tx,
    input wire keys_ready, song_busy, notes_busy, recording,
    output reg [55:0] note_map,
    input wire [6:0] touch_keys,
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
    output reg xy_write,
    output reg [1:0] xy_ratio,xy_phase,
    output reg visual_write,
    output reg [1:0] remote_mode,
    input wire [1:0] visual_requested,reference_ratio,reference_phase,
    input wire [111:0] visual_snapshot,
    output reg touch_mode16,touch_hold,panic,serial_active_high,
    output reg [1:0] effect_mode,
    output reg [3:0] effect_wet,
    output reg [4:0] master_volume,
    output reg [2:0] analog_mode,
    output reg pressure_write,pressure_value,
    output reg [9:0] analog_min,analog_max,
    input wire [9:0] adc_sample,
    input wire adc_timeout,
    input wire audio_rec_busy,audio_rec_ready,audio_rec_overflow,
    output reg audio_rec_start,audio_rec_stop,audio_rec_abort,
    output reg [15:0] audio_rec_session,
    output reg [2:0] take_command,
    input wire [7:0] take_flags,
    input wire [3:0] take_error,
    input wire [23:0] take_elapsed,take_duration,
    input wire [10:0] take_count
);
    localparam [55:0] DEFAULT_MAP={8'd71,8'd69,8'd67,8'd65,8'd64,8'd62,8'd60};
    localparam COLLECT=0, EXECUTE=1, RESPOND=2, DECIMAL=3, SONG_WAIT=4, DECIMAL_READ=5, ADSR_WAIT=6;
    localparam NO_ERROR=0, LENGTH_ERROR=1, CHAR_ERROR=2, UART_ERROR=3;
    reg [3:0] state;
    reg [1:0] line_error;
    reg [95:0] line;
    reg [95:0] prefix; // First eleven bytes, shared fixed-position command decoder.
    reg [6:0] line_length, parse_length, position;
    reg [255:0] reply;
    reg visual_reply,take_reply;
    reg [5:0] reply_remaining;
    wire [7:0] received;
    wire [7:0] reply_byte;
    wire received_valid, rx_fault, tx_ready;
    reg log_owned;
    wire [7:0] log_data;
    wire log_valid, log_last, log_ready;
    wire select_log=log_owned || (state!=RESPOND && log_valid);
    wire [7:0] requested_note=(line[15:8]-8'd48)*8'd10+(line[7:0]-8'd48);
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
    (* syn_ramstyle="block_ram" *) reg [7:0] command_bytes [0:63];
    reg [7:0] ch;
    reg adsr_parse,adsr_target,adsr_request,adsr_restore;
    reg bend_parse;
    reg [3:0] control_parse;
    reg [15:0] adsr_a,adsr_d,adsr_s,adsr_r;
    wire adsr_done;
    integer prefix_byte;
    always @(posedge clk) begin
        ch<=command_bytes[position[5:0]];
        if(resetn && state==COLLECT && received_valid && line_error==NO_ERROR &&
           line_length<64 && received>=32 && received<=126)
            command_bytes[line_length[5:0]]<=received;
    end
    adsr_config #(.DEFAULT_A(DEFAULT_A),.DEFAULT_D(DEFAULT_D),.DEFAULT_S(DEFAULT_S),.DEFAULT_R(DEFAULT_R)) u_adsr_config (
        .clk(clk),.resetn(resetn),.request(adsr_request),.restore(adsr_restore),.profile(adsr_target),
        .attack_ms(adsr_a),.decay_ms(adsr_d),.sustain_percent(adsr_s),.release_ms(adsr_r),
        .done(adsr_done),.touch_config(touch_adsr),.sensor_config(sensor_adsr));
    assign log_ready=select_log && tx_ready;
    uart_8n1 #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_uart (
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),
        .rx_data(received),.rx_valid(received_valid),.rx_ready(state==COLLECT),
        .rx_fault(rx_fault),.tx_data(select_log ? log_data : reply_byte),
        .tx_valid(select_log ? log_valid : state==RESPOND),.tx_ready(tx_ready)
    );
    downloadable_song #(.CLK_HZ(CLK_HZ),.ENABLE_LOOKAHEAD(ENABLE_LOOKAHEAD),
        .LOOKAHEAD_MS(LOOKAHEAD_MS)) u_download (
        .clk(clk),.resetn(resetn),.request(song_request),.operation(song_operation),
        .arg3(16'd0),.score_min(16'd8192),.score_max(16'd32768),.arg0(song_arg0),.arg1(song_arg1),.arg2(song_arg2),.edit_allowed(edit_allowed),
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
    generate if(!ENABLE_EVENT_TAKE)begin: legacy_log
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
    // Serialize one nibble at a time through a single hex encoder. Reusing
    // reply storage avoids 28 parallel encoders on this nearly full device.
    wire take_digit=reply_remaining==24 || reply_remaining==23 || reply_remaining==21 ||
        (reply_remaining<=19 && reply_remaining>=14) ||
        (reply_remaining<=12 && reply_remaining>=10) ||
        (reply_remaining<=8 && reply_remaining>=3);
    wire [7:0] encoded_hex=hex_char(reply[255:252]);
    assign reply_byte = take_reply ?
        (reply_remaining==29 ? "T" : reply_remaining==28 ? "A" :
         reply_remaining==27 ? "K" : reply_remaining==26 ? "E" :
         take_digit ? encoded_hex : reply_remaining==2 ? 8'd13 : reply_remaining==1 ? 8'd10 : ",") :
        !visual_reply ? reply[255:248] :
        reply_remaining==32 ? "V" : reply_remaining==31 ? "," :
        reply_remaining==2 ? 8'd13 : reply_remaining==1 ? 8'd10 : encoded_hex;
    function [7:0] tens;
        input [7:0] note;
        begin tens=(note<70) ? "6" : "7"; end
    endfunction
    function [7:0] ones;
        input [7:0] note;
        begin ones=8'd48+((note<70) ? note-8'd60 : note-8'd70); end
    endfunction
    task respond;
        input [255:0] message;
        input [5:0] length;
        begin reply<=message << ((32-length)*8); reply_remaining<=length; visual_reply<=0;take_reply<=0;state<=RESPOND; end
    endtask
    task result;
        input [2:0] error_code;
        begin
            case(error_code)
                0: respond({"OK",8'd13,8'd10},4);
                1: respond({"ERR,BUSY",8'd13,8'd10},10);
                2: respond({"ERR,RANGE",8'd13,8'd10},11);
                3: respond({"ERR,STATE",8'd13,8'd10},11);
                4: respond({"ERR,MISSING",8'd13,8'd10},13);
                5: respond({"ERR,MAP",8'd13,8'd10},9);
                default: respond({"ERR,CMD",8'd13,8'd10},9);
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
            line<=0; prefix<=0; line_length<=0; reply<=0; reply_remaining<=0; visual_reply<=0;take_reply<=0;log_owned<=0;
            song_request<=0; rec_start<=0; rec_stop<=0;
            downloaded_audition<=0; audition_pending<=0;
            song_operation<=0; song_arg0<=0; song_arg1<=0; song_arg2<=0;
            builtin_play<=0; builtin_stop<=0;
            guitar_pluck<=0; gesture_timbre<=0; gesture_vibrato<=0; gesture_bank<=0;
            sensor_test32<=0;
            audio_rec_start<=0;audio_rec_stop<=0;audio_rec_abort<=0;audio_rec_session<=0;take_command<=0;
            touch_mode16<=ENABLE_EVENT_TAKE!=0;serial_active_high<=0;touch_hold<=0;panic<=0;effect_mode<=0;effect_wet<=4;
            master_volume<=16;analog_mode<=0;analog_min<=0;analog_max<=1023;pressure_write<=0;pressure_value<=0;control_parse<=0;
            xy_write<=0;xy_ratio<=2;xy_phase<=0;
            visual_write<=0;remote_mode<=0;
            bend_parse<=0;bend_write<=0;bend_reset<=0;bend_index<=0;bend_ratio<=16384;
            adsr_parse<=0;adsr_target<=0;adsr_request<=0;adsr_restore<=0;
            adsr_a<=0;adsr_d<=0;adsr_s<=0;adsr_r<=0;value2<=0;
            field_index<=0; field_count<=0; accumulator<=0; value0<=0; value1<=0;
            have_digit<=0; parse_length<=0; position<=0;
        end else begin
            song_request<=0; rec_start<=0; rec_stop<=0; builtin_play<=0; builtin_stop<=0;
            guitar_pluck<=0;panic<=0;pressure_write<=0;
            sensor_test32<=0;adsr_request<=0;
            bend_write<=0;bend_reset<=0;
            xy_write<=0;
            visual_write<=0;
            audio_rec_start<=0;audio_rec_stop<=0;audio_rec_abort<=0;
            take_command<=0;
            // Audition is opt-in for one UART start only. Physical controls
            // always return to silent guidance; ending a score disarms it.
            if(!downloaded_playing) downloaded_audition<=0;
            if(select_log && log_valid && tx_ready) log_owned<=!log_last;
            if(rx_fault) begin
                line_error<=UART_ERROR;
                if(state==COLLECT || state==EXECUTE) begin line<=0; line_length<=0; state<=COLLECT; end
            end
            if(state==RESPOND) begin
                if(!select_log && tx_ready) begin
                    if(!visual_reply && !take_reply)reply<={reply[247:0],8'd0};
                    else if((take_reply && take_digit) || (visual_reply && reply_remaining<=30 && reply_remaining>=3))reply<={reply[251:0],4'd0};
                    reply_remaining<=reply_remaining-1'b1;
                    if(reply_remaining==1) state<=COLLECT;
                end
            end else if(!rx_fault || (state!=COLLECT && state!=EXECUTE)) begin
                case(state)
                    COLLECT: if(received_valid) begin
                        if(received==13 || received==10) begin
                            if(line_length!=0 || line_error!=NO_ERROR) state<=EXECUTE;
                        end else if(line_error==NO_ERROR) begin
                            if(line_length==64) line_error<=LENGTH_ERROR;
                            else if(received<32 || received>126) line_error<=CHAR_ERROR;
                            else begin
                                if(line_length==0) prefix<={received,88'd0};
                                else for(prefix_byte=1;prefix_byte<12;prefix_byte=prefix_byte+1)
                                    if(line_length==prefix_byte) prefix[95-prefix_byte*8 -: 8]<=received;
                                line<=line_length==0 ? {88'd0,received} : {line[87:0],received};
                                line_length<=line_length+1'b1;
                            end
                        end
                    end
                    EXECUTE: begin
                        line_length<=0; line_error<=NO_ERROR;adsr_parse<=0;adsr_restore<=0;bend_parse<=0;control_parse<=0;
                        if(line_error==UART_ERROR) respond({"ERR,UART",8'd13,8'd10},10);
                        else if(line_error==LENGTH_ERROR) respond({"ERR,LENGTH",8'd13,8'd10},12);
                        else if(line_error==CHAR_ERROR) respond({"ERR,CMD",8'd13,8'd10},9);
                        else if(line_length==4 && line[31:0]=="PING") respond({"PONG",8'd13,8'd10},6);
                        else if(line_length==5 && line[39:0]=="CTRL?") begin
                            respond({"CTRL,",8'd48+{7'd0,touch_mode16},",",8'd48+{6'd0,effect_mode},",",
                                8'd48+{4'd0,effect_wet},",",8'd48+{7'd0,touch_hold},",",
                                8'd48+{5'd0,analog_mode},",",(master_volume>=10 ? 8'd49 : 8'd48),
                                8'd48+(master_volume>=10 ? master_volume-8'd10 : {3'd0,master_volume}),",",
                                8'd48+{7'd0,pressure_mode},8'd13,8'd10},21);
                        end else if(line_length==7 && line[55:0]=="SERIAL?") begin
                            respond({"SERIAL,",8'd48+{7'd0,serial_active_high},8'd13,8'd10},10);
                        end else if(line_length>7 && prefix[95:40]=="SERIAL,") begin
                            control_parse<=8;parse_numbers(7,1);
                        end else if(line_length==4 && line[31:0]=="CAL?") begin
                            respond({"CAL,",hex_char({2'd0,analog_min[9:8]}),hex_char(analog_min[7:4]),hex_char(analog_min[3:0]),",",
                                hex_char({2'd0,analog_max[9:8]}),hex_char(analog_max[7:4]),hex_char(analog_max[3:0]),8'd13,8'd10},13);
                        end else if(line_length>4 && prefix[95:64]=="CAL,") begin
                            control_parse<=7;parse_numbers(4,2);
                        end else if(line_length==4 && line[31:0]=="ADC?") begin
                            respond({"ADC,",hex_char({2'd0,adc_sample[9:8]}),hex_char(adc_sample[7:4]),
                                hex_char(adc_sample[3:0]),",",8'd48+{7'd0,adc_timeout},8'd13,8'd10},11);
                        end else if(line_length==5 && line[39:0]=="PANIC") begin
                            panic<=1;touch_hold<=0;downloaded_audition<=0;audition_pending<=0;
                            builtin_stop<=1;song_request<=1;song_operation<=5;state<=SONG_WAIT;
                        end else if(line_length>6 && prefix[95:48]=="TOUCH,") begin
                            control_parse<=1;parse_numbers(6,1);
                        end else if(line_length>7 && prefix[95:40]=="EFFECT,") begin
                            control_parse<=2;parse_numbers(7,2);
                        end else if(line_length>5 && prefix[95:56]=="HOLD,") begin
                            control_parse<=3;parse_numbers(5,1);
                        end else if(line_length>7 && prefix[95:40]=="VOLUME,") begin
                            control_parse<=4;parse_numbers(7,1);
                        end else if(line_length>7 && prefix[95:40]=="ANALOG,") begin
                            control_parse<=5;parse_numbers(7,1);
                        end else if(line_length>9 && prefix[95:24]=="PRESSURE,") begin
                            control_parse<=6;parse_numbers(9,1);
                        end
                        else if(line_length==5 && line[39:0]=="TAKE?" && ENABLE_EVENT_TAKE)begin
                            reply<={take_flags,take_error,take_elapsed,1'b0,take_count,take_duration,184'd0};
                            reply_remaining<=29;visual_reply<=0;take_reply<=1;state<=RESPOND;
                        end else if(ENABLE_EVENT_TAKE &&
                            ((line_length==8 && (line[63:0]=="TAKE_REC" || line[63:0]=="TAKE_DEL" || line[63:0]=="TAKE_YES")) ||
                             (line_length==9 && (line[71:0]=="TAKE_STOP" || line[71:0]=="TAKE_PLAY" || line[71:0]=="TAKE_SAVE")) ||
                             (line_length==7 && line[55:0]=="TAKE_NO")))begin
                            if(line_length==9 && line[71:0]=="TAKE_STOP")begin take_command<=2;result(0);end
                            else if(take_flags[5] || take_flags[1:0]!=0)result(1);
                            else begin
                                if(line_length==8 && line[63:0]=="TAKE_REC")take_command<=1;
                                else if(line_length==9)take_command<=line[71:0]=="TAKE_SAVE" ? 3'd7 : 3'd3;
                                else if(line_length==8 && line[63:0]=="TAKE_DEL")take_command<=4;
                                else if(line_length==8)take_command<=5;
                                else take_command<=6;
                                result(0);
                            end
                        end
                        else if(line_length>11 && prefix[95:8]=="AREC_START,")begin
                            control_parse<=9;parse_numbers(11,1);
                        end else if(line_length==9 && line[71:0]=="AREC_STOP")begin
                            audio_rec_stop<=1;result(0);
                        end else if(line_length==10 && line[79:0]=="AREC_ABORT")begin
                            audio_rec_abort<=1;result(0);
                        end else if(line_length==5 && line[39:0]=="AREC?")begin
                            respond({"AREC,",8'd48+{7'd0,audio_rec_busy},",",8'd48+{7'd0,audio_rec_ready},",",
                                8'd48+{7'd0,audio_rec_overflow},8'd13,8'd10},12);
                        end
                        else if(line_length==5 && line[39:8]=="VIS,") begin
                            if(line[7:0]>="0" && line[7:0]<="3") begin
                                remote_mode<=line[1:0];visual_write<=1;result(0);
                            end else result(2);
                        end else if(line_length==4 && line[31:0]=="VIS?") begin
                            respond({"VIS,",8'd48+{6'd0,visual_requested},",",
                                8'd48+{6'd0,visual_snapshot[103:102]},",",
                                8'd48+{6'd0,reference_ratio},",",8'd48+{6'd0,reference_phase},",",
                                8'd48+{6'd0,visual_snapshot[101:100]},",",8'd48+{6'd0,visual_snapshot[99:98]},",",
                                hex_char(visual_snapshot[107:104]),8'd13,8'd10},19);
                        end else if(line_length==4 && line[31:0]=="VIZ?") begin
                            // Exactly 32 UART bytes, captured atomically into the existing reply register.
                            reply<={visual_snapshot,144'd0};reply_remaining<=32;visual_reply<=1;take_reply<=0;state<=RESPOND;
                        end
                        else if(line_length==6 && prefix[95:72]=="XY," && line[15:8]==",") begin
                            if(line[23:16]>="0" && line[23:16]<="3" && line[7:0]>="0" && line[7:0]<="3") begin
                                xy_ratio<=line[17:16];xy_phase<=line[1:0];xy_write<=1;result(0);
                            end else result(2);
                        end
                        else if(line_length>5 && prefix[95:56]=="BEND,") begin
                            bend_parse<=1;parse_numbers(5,2);
                        end else if(line_length==10 && line[79:0]=="BEND_RESET") begin
                            bend_reset<=1;result(0);
                        end
                        else if(line_length>11 && prefix[95:8]=="ADSR,TOUCH,") begin
                            adsr_parse<=1;adsr_target<=0;parse_numbers(11,4);
                        end else if(line_length>12 && prefix=="ADSR,SENSOR,") begin
                            adsr_parse<=1;adsr_target<=1;parse_numbers(12,4);
                        end else if(prefix[95:8]=="ADSR_RESET," &&
                            ((line_length==16 && line[39:0]=="TOUCH") || (line_length==17 && line[47:0]=="SENSOR"))) begin
                            adsr_target<=line_length==17;adsr_request<=1;adsr_restore<=1;state<=ADSR_WAIT;
                        end else if(line_length==6 && line[47:0]=="TEST32") begin
                            sensor_test32<=1; gesture_vibrato<=0; result(0);
                        end else if(line_length==6 && line[47:0]=="GUITAR") begin
                            guitar_pluck<=1; result(0);
                        end else if(line_length==6 && line[47:8]=="TONE,") begin
                            if(line[7:0]<"0" || line[7:0]>"9") result(7);
                            else if(line[7:0]>"7") result(2);
                            else begin gesture_timbre<=line[2:0]; result(0); end
                        end else if(line_length==9 && line[71:8]=="VIBRATO,") begin
                            if(line[7:0]<"0" || line[7:0]>"9") result(7);
                            else if(line[7:0]>"1") result(2);
                            else begin gesture_vibrato<=line[0]; result(0); end
                        end else if(line_length==6 && line[47:8]=="BANK,") begin
                            if(line[7:0]<"0" || line[7:0]>"9") result(7);
                            else if(line[7:0]>"1") result(2);
                            else begin gesture_bank<=line[0]; result(0); end
                        end
                        else if(line_length==4 && line[31:0]=="MAP?") begin
                            respond({"MAP,",tens(note_map[7:0]),ones(note_map[7:0]),",",
                                tens(note_map[15:8]),ones(note_map[15:8]),",",
                                tens(note_map[23:16]),ones(note_map[23:16]),",",
                                tens(note_map[31:24]),ones(note_map[31:24]),",",
                                tens(note_map[39:32]),ones(note_map[39:32]),",",
                                tens(note_map[47:40]),ones(note_map[47:40]),",",
                                tens(note_map[55:48]),ones(note_map[55:48]),8'd13,8'd10},26);
                        end else if(line_length==9 && line[71:0]=="MAP_RESET") begin
                            if(!edit_allowed) result(1);
                            else begin note_map<=DEFAULT_MAP; respond({"OK,MAP_RESET",8'd13,8'd10},14); end
                        end else if(line_length==8 && line[63:32]=="MAP," && line[23:16]==",") begin
                            if(line[31:24]<"1" || line[31:24]>"7") respond({"ERR,KEY",8'd13,8'd10},9);
                            else if(line[15:8]<"0" || line[15:8]>"9" || line[7:0]<"0" || line[7:0]>"9") result(7);
                            else if(requested_note<60 || requested_note>72) respond({"ERR,NOTE",8'd13,8'd10},10);
                            else if(!edit_allowed) result(1);
                            else begin
                                note_map[(line[31:24]-8'd49)*8 +: 8]<=requested_note;
                                respond({"OK,MAP,",line[31:24],",",line[15:0],8'd13,8'd10},13);
                            end
                        end else if(line_length>11 && prefix[95:8]=="SONG_BEGIN,") begin
                            song_operation<=1; parse_numbers(11,1);
                        end else if(line_length>10 && prefix[95:16]=="SONG_NOTE,") begin
                            song_operation<=2; parse_numbers(10,3);
                        end else if(line_length>11 && prefix[95:8]=="SONG_CHORD,") begin
                            song_operation<=6; parse_numbers(11,3);
                        end else if(line_length==8 && line[63:0]=="SONG_END") begin
                            song_request<=1; song_operation<=3; state<=SONG_WAIT;
                        end else if(line_length==4 && line[31:0]=="PLAY") begin
                            if(!keys_ready) result(1);
                            else begin
                                 downloaded_audition<=0; audition_pending<=0;
                                if(downloaded_valid) begin song_request<=1; song_operation<=4; state<=SONG_WAIT; end
                                else if(ENABLE_DEMO_SCORE) begin builtin_play<=1; result(0); end
                                else result(3);
                            end
                         end else if(line_length==8 && line[63:0]=="AUDITION") begin
                             if(!keys_ready || rec_busy || recording) result(1);
                             else if(!downloaded_valid) result(3);
                             else begin
                                 downloaded_audition<=0; audition_pending<=1;
                                 song_request<=1; song_operation<=4; state<=SONG_WAIT;
                             end
                         end else if(line_length==4 && line[31:0]=="STOP") begin
                             downloaded_audition<=0; audition_pending<=0;
                            builtin_stop<=1; song_request<=1; song_operation<=5;
                            state<=SONG_WAIT;
                        end else if(line_length==9 && line[71:0]=="REC_START") begin
                            if(ENABLE_EVENT_TAKE)result(3);
                            else if(!keys_ready || rec_busy || recording || touch_mode16 || touch_hold || analog_mode!=0) result(1);
                            else begin rec_start<=1; result(0); end
                        end else if(line_length==8 && line[63:0]=="REC_STOP") begin rec_stop<=1; result(0); end
                        else result(7);
                    end
                    DECIMAL_READ:state<=DECIMAL;
                    ADSR_WAIT:if(adsr_done && !adsr_request) result(0);
                    DECIMAL: begin
                        if(position==parse_length) begin
                            if(!have_digit || field_count==0 || field_index!=field_count-1) result(7);
                            else if(control_parse!=0) begin
                                case(control_parse)
                                    1:if(accumulator!=8 && accumulator!=16)result(2);
                                      else if(!edit_allowed || touch_hold)result(1);
                                      else begin touch_mode16<=accumulator==16;result(0);end
                                    2:if(value0>2 || accumulator>8)result(2);
                                      else begin effect_mode<=value0[1:0];effect_wet<=accumulator[3:0];result(0);end
                                    3:if(accumulator>1)result(2);
                                      else if(rec_busy || recording)result(1);
                                      else begin touch_hold<=accumulator[0];result(0);end
                                    4:if(accumulator>16)result(2);
                                      else begin master_volume<=accumulator[4:0];result(0);end
                                    5:if(accumulator>4)result(2);
                                      else if(rec_busy || recording)result(1);
                                      else begin analog_mode<=accumulator[2:0];result(0);end
                                    6:if(accumulator>1)result(2);
                                      else begin pressure_write<=1;pressure_value<=accumulator[0];result(0);end
                                    7:if(value0>1023 || accumulator>1023 || accumulator<=value0 || accumulator-value0<32)result(2);
                                      else if(rec_busy || recording)result(1);
                                      else begin analog_min<=value0[9:0];analog_max<=accumulator[9:0];result(0);end
                                    8:if(accumulator>1)result(2);
                                      else if(!edit_allowed || touch_hold)result(1);
                                      else begin serial_active_high<=accumulator[0];result(0);end
                                    9:if(audio_rec_busy)result(1);
                                      else if(!audio_rec_ready)result(3);
                                      else begin audio_rec_session<=accumulator;audio_rec_start<=1;result(0);end
                                    default:result(7);
                                endcase
                            end else if(bend_parse) begin
                                if(value0<1 || value0>7 || accumulator<8192 || accumulator>32768) result(2);
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
                            if(!have_digit) result(7);
                            else if(field_index>=field_count-1) result(7);
                            else begin
                                if(field_index==0) value0<=accumulator; else if(field_index==1) value1<=accumulator; else value2<=accumulator;
                                accumulator<=0; have_digit<=0; field_index<=field_index+1'b1; position<=position+1'b1;state<=DECIMAL_READ;
                            end
                        end else if(ch<"0" || ch>"9") result(7);
                        else if(accumulator>6553 || (accumulator==6553 && ch>"5")) result(2);
                        else begin accumulator<=accumulator*16'd10+(ch-8'd48); have_digit<=1; position<=position+1'b1;state<=DECIMAL_READ; end
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
        end
    end
endmodule

