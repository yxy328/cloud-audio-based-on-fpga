`timescale 1ns/1ps
// Case-sensitive ASCII lines, CR/LF/CRLF, <=64 characters excluding EOL.
// Command replies and performance records share UART at complete-line boundaries.
module hc05_keymap #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer BAUD=9600
) (
    input wire clk, resetn, rx,
    output wire tx,
    input wire keys_ready, song_busy, notes_busy, recording,
    output reg [55:0] note_map,
    input wire [6:0] touch_keys,
    input wire pressure_mode,
    input wire [15:0] volume_gain, pitch_ratio,
    input wire sample_ce, toggle_play, restart,
    output wire rec_busy,
    output wire downloaded_valid, downloaded_playing, downloaded_gate,
    output wire [31:0] downloaded_increment,
    output wire [6:0] guide_keys,
    output wire pcm_valid, pcm_playing,
    output wire signed [15:0] pcm_sample,
    output reg builtin_play, builtin_stop
);
    localparam [55:0] DEFAULT_MAP={8'd71,8'd69,8'd67,8'd65,8'd64,8'd62,8'd60};
    localparam COLLECT=0, EXECUTE=1, RESPOND=2, DECIMAL=3, SONG_WAIT=4,
        PCM_WAIT=5, HEX_HIGH=6, HEX_LOW=7, PCM_BYTE_WAIT=8;
    localparam NO_ERROR=0, LENGTH_ERROR=1, CHAR_ERROR=2, UART_ERROR=3;
    reg [3:0] state;
    reg [1:0] line_error;
    reg [511:0] line;
    reg [87:0] prefix; // First eleven bytes, shared fixed-position command decoder.
    reg [6:0] line_length, parse_length, position;
    reg [255:0] reply;
    reg [5:0] reply_remaining;
    wire [7:0] received;
    wire received_valid, rx_fault, tx_ready;
    reg log_owned;
    wire [7:0] log_data;
    wire log_valid, log_last, log_ready;
    wire select_log=log_owned || (state!=RESPOND && log_valid);
    wire [7:0] requested_note=(line[15:8]-8'd48)*8'd10+(line[7:0]-8'd48);
    wire edit_allowed=keys_ready && !song_busy && !notes_busy && !recording && !rec_busy;
    reg song_request, pcm_request, rec_start, rec_stop;
    reg [2:0] song_operation, pcm_operation;
    reg [15:0] song_arg0, song_arg1, song_arg2, pcm_arg0, pcm_arg1, pcm_arg2;
    wire song_done, pcm_done;
    wire [2:0] song_error, pcm_error;
    wire [7:0] download_note;
    wire [223:0] download_steps;
    reg decimal_pcm;
    reg [1:0] field_index, field_count;
    reg [15:0] accumulator, value0, value1;
    reg have_digit;
    reg [3:0] high_nibble;
    reg [4:0] block_bytes;
    wire [5:0] char_offset=parse_length[5:0]-6'd1-position[5:0];
    wire [7:0] ch=line[{char_offset,3'b000} +: 8];
    wire [4:0] hex_value=(ch>="0" && ch<="9") ? {1'b0,ch[3:0]} :
        (ch>="A" && ch<="F") ? ch[4:0]+5'd9 :
        (ch>="a" && ch<="f") ? ch[4:0]+5'd9 : 5'd16;
    assign downloaded_increment=download_steps[31:0];
    assign log_ready=select_log && tx_ready;
    uart_8n1 #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_uart (
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),
        .rx_data(received),.rx_valid(received_valid),.rx_ready(state==COLLECT),
        .rx_fault(rx_fault),.tx_data(select_log ? log_data : reply[255:248]),
        .tx_valid(select_log ? log_valid : state==RESPOND),.tx_ready(tx_ready)
    );
    downloadable_song #(.CLK_HZ(CLK_HZ)) u_download (
        .clk(clk),.resetn(resetn),.request(song_request),.operation(song_operation),
        .arg0(song_arg0),.arg1(song_arg1),.arg2(song_arg2),.edit_allowed(edit_allowed),
        .note_map(note_map),.toggle_play(toggle_play && !pcm_valid),.restart(restart && !pcm_valid),
        .done(song_done),.error(song_error),.valid(downloaded_valid),.playing(downloaded_playing),
        .gate(downloaded_gate),.current_note(download_note),.guide_keys(guide_keys)
    );
    midi_note_lut u_download_lut (
        .clk(clk),.resetn(resetn),.note_map({7{download_note}}),.phase_increments(download_steps)
    );
    pcm_clip_player u_pcm (
        .clk(clk),.resetn(resetn),.sample_ce(sample_ce),.request(pcm_request),.operation(pcm_operation),
        .arg0(pcm_arg0),.arg1(pcm_arg1),.arg2(pcm_arg2),.edit_allowed(edit_allowed),
        .toggle_play(toggle_play && pcm_valid),.restart(restart && pcm_valid),
        .done(pcm_done),.error(pcm_error),.valid(pcm_valid),.playing(pcm_playing),.sample(pcm_sample)
    );
    performance_logger #(.CLK_HZ(CLK_HZ)) u_logger (
        .clk(clk),.resetn(resetn),.start(rec_start),.stop(rec_stop),.note_map(note_map),
        .touch_keys(touch_keys),.pressure_mode(pressure_mode),.volume_gain(volume_gain),.pitch_ratio(pitch_ratio),
        .recording(rec_busy),.tx_data(log_data),.tx_valid(log_valid),.tx_last(log_last),.tx_ready(log_ready),.dropped()
    );
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
        begin reply<=message << ((32-length)*8); reply_remaining<=length; state<=RESPOND; end
    endtask
    task result;
        input [2:0] error_code;
        input is_pcm;
        begin
            case(error_code)
                0: respond({"OK",8'd13,8'd10},4);
                1: respond({"ERR,BUSY",8'd13,8'd10},10);
                2: respond({"ERR,RANGE",8'd13,8'd10},11);
                3: respond({"ERR,STATE",8'd13,8'd10},11);
                4: respond({"ERR,MISSING",8'd13,8'd10},13);
                5: if(is_pcm) respond({"ERR,CHECKSUM",8'd13,8'd10},14);
                   else respond({"ERR,MAP",8'd13,8'd10},9);
                default: respond({"ERR,CMD",8'd13,8'd10},9);
            endcase
        end
    endtask
    task parse_numbers;
        input [6:0] first_position;
        input [1:0] fields;
        input is_pcm;
        begin
            parse_length<=line_length; position<=first_position; field_count<=fields;
            field_index<=0; accumulator<=0; value0<=0; value1<=0; have_digit<=0;
            decimal_pcm<=is_pcm; state<=DECIMAL;
        end
    endtask
    always @(posedge clk) begin
        if(!resetn) begin
            note_map<=DEFAULT_MAP; state<=COLLECT; line_error<=NO_ERROR;
            line<=0; prefix<=0; line_length<=0; reply<=0; reply_remaining<=0; log_owned<=0;
            song_request<=0; pcm_request<=0; rec_start<=0; rec_stop<=0;
            song_operation<=0; pcm_operation<=0; song_arg0<=0; song_arg1<=0; song_arg2<=0;
            pcm_arg0<=0; pcm_arg1<=0; pcm_arg2<=0; builtin_play<=0; builtin_stop<=0;
            decimal_pcm<=0; field_index<=0; field_count<=0; accumulator<=0; value0<=0; value1<=0;
            have_digit<=0; high_nibble<=0; block_bytes<=0; parse_length<=0; position<=0;
        end else begin
            song_request<=0; pcm_request<=0; rec_start<=0; rec_stop<=0; builtin_play<=0; builtin_stop<=0;
            // Physical controls select the downloaded PCM when present.
            // Stop the other source as well so it cannot continue silently.
            if(pcm_valid && (toggle_play || restart)) begin
                song_request<=1; song_operation<=5; builtin_stop<=1;
            end
            if(select_log && log_valid && tx_ready) log_owned<=!log_last;
            if(rx_fault) begin
                line_error<=UART_ERROR;
                if(state==COLLECT || state==EXECUTE) begin line<=0; line_length<=0; state<=COLLECT; end
            end
            if(state==RESPOND) begin
                if(!select_log && tx_ready) begin
                    reply<={reply[247:0],8'd0}; reply_remaining<=reply_remaining-1'b1;
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
                                if(line_length==0) prefix<={80'd0,received};
                                else if(line_length<11) prefix<={prefix[79:0],received};
                                line<=line_length==0 ? {504'd0,received} : {line[503:0],received};
                                line_length<=line_length+1'b1;
                            end
                        end
                    end
                    EXECUTE: begin
                        line_length<=0; line_error<=NO_ERROR;
                        if(line_error==UART_ERROR) respond({"ERR,UART",8'd13,8'd10},10);
                        else if(line_error==LENGTH_ERROR) respond({"ERR,LENGTH",8'd13,8'd10},12);
                        else if(line_error==CHAR_ERROR) respond({"ERR,CMD",8'd13,8'd10},9);
                        else if(line_length==4 && line[31:0]=="PING") respond({"PONG",8'd13,8'd10},6);
                        else if(line_length==4 && line[31:0]=="MAP?") begin
                            respond({"MAP,",tens(note_map[7:0]),ones(note_map[7:0]),",",
                                tens(note_map[15:8]),ones(note_map[15:8]),",",
                                tens(note_map[23:16]),ones(note_map[23:16]),",",
                                tens(note_map[31:24]),ones(note_map[31:24]),",",
                                tens(note_map[39:32]),ones(note_map[39:32]),",",
                                tens(note_map[47:40]),ones(note_map[47:40]),",",
                                tens(note_map[55:48]),ones(note_map[55:48]),8'd13,8'd10},26);
                        end else if(line_length==9 && line[71:0]=="MAP_RESET") begin
                            if(!edit_allowed) result(1,0);
                            else begin note_map<=DEFAULT_MAP; respond({"OK,MAP_RESET",8'd13,8'd10},14); end
                        end else if(line_length==8 && line[63:32]=="MAP," && line[23:16]==",") begin
                            if(line[31:24]<"1" || line[31:24]>"7") respond({"ERR,KEY",8'd13,8'd10},9);
                            else if(line[15:8]<"0" || line[15:8]>"9" || line[7:0]<"0" || line[7:0]>"9") result(7,0);
                            else if(requested_note<60 || requested_note>72) respond({"ERR,NOTE",8'd13,8'd10},10);
                            else if(!edit_allowed) result(1,0);
                            else begin
                                note_map[(line[31:24]-8'd49)*8 +: 8]<=requested_note;
                                respond({"OK,MAP,",line[31:24],",",line[15:0],8'd13,8'd10},13);
                            end
                        end else if(line_length>11 && prefix=="SONG_BEGIN,") begin
                            song_operation<=1; parse_numbers(11,1,0);
                        end else if(line_length>10 && prefix[87:8]=="SONG_NOTE,") begin
                            song_operation<=2; parse_numbers(10,3,0);
                        end else if(line_length==8 && line[63:0]=="SONG_END") begin
                            song_request<=1; song_operation<=3; state<=SONG_WAIT;
                        end else if(line_length==4 && line[31:0]=="PLAY") begin
                            if(!keys_ready) result(1,0);
                            else begin
                                pcm_request<=1; pcm_operation<=5;
                                if(downloaded_valid) begin song_request<=1; song_operation<=4; state<=SONG_WAIT; end
                                else begin builtin_play<=1; result(0,0); end
                            end
                        end else if(line_length==4 && line[31:0]=="STOP") begin
                            builtin_stop<=1; song_request<=1; song_operation<=5;
                            pcm_request<=1; pcm_operation<=5; state<=SONG_WAIT;
                        end else if(line_length==9 && line[71:0]=="REC_START") begin
                            if(!keys_ready || rec_busy || recording) result(1,0);
                            else begin rec_start<=1; result(0,0); end
                        end else if(line_length==8 && line[63:0]=="REC_STOP") begin rec_stop<=1; result(0,0); end
                        else if(line_length>10 && prefix[87:8]=="PCM_BEGIN,") begin
                            pcm_operation<=1; parse_numbers(10,2,1);
                        end else if(line_length>9 && prefix[87:16]=="PCM_DATA,") begin
                            // field_count=0 selects decimal offset followed by hex data.
                            block_bytes<=0; pcm_operation<=2; parse_numbers(9,0,1);
                        end else if(line_length==7 && line[55:0]=="PCM_END") begin
                            pcm_request<=1; pcm_operation<=3; state<=PCM_WAIT;
                        end else if(line_length==8 && line[63:0]=="PCM_PLAY") begin
                            if(!keys_ready) result(1,1);
                            else begin
                                builtin_stop<=1; song_request<=1; song_operation<=5;
                                pcm_request<=1; pcm_operation<=4; state<=PCM_WAIT;
                            end
                        end else if(line_length==8 && line[63:0]=="PCM_STOP") begin
                            pcm_request<=1; pcm_operation<=5; state<=PCM_WAIT;
                        end else result(7,0);
                    end
                    DECIMAL: begin
                        if(position==parse_length) begin
                            if(!have_digit || field_count==0 || field_index!=field_count-1) result(7,0);
                            else if(decimal_pcm) begin
                                pcm_arg0<=value0; pcm_arg1<=accumulator; pcm_arg2<=0;
                                pcm_request<=1; state<=PCM_WAIT;
                            end else begin
                                song_arg0<=(field_count==1) ? accumulator : value0;
                                song_arg1<=value1; song_arg2<=accumulator;
                                song_request<=1; state<=SONG_WAIT;
                            end
                        end else if(ch==",") begin
                            if(!have_digit) result(7,0);
                            else if(field_count==0) begin
                                if(parse_length-position-1==0 || parse_length-position-1>32 || ((parse_length-position-1)&1)) result(7,1);
                                else begin value0<=accumulator; position<=position+1'b1; state<=HEX_HIGH; end
                            end else if(field_index>=field_count-1) result(7,0);
                            else begin
                                if(field_index==0) value0<=accumulator; else value1<=accumulator;
                                accumulator<=0; have_digit<=0; field_index<=field_index+1'b1; position<=position+1'b1;
                            end
                        end else if(ch<"0" || ch>"9") result(7,0);
                        else if(accumulator>6553 || (accumulator==6553 && ch>"5")) result(2,decimal_pcm);
                        else begin accumulator<=accumulator*16'd10+(ch-8'd48); have_digit<=1; position<=position+1'b1; end
                    end
                    SONG_WAIT: if(song_done) result(song_error,0);
                    PCM_WAIT: if(pcm_done) result(pcm_error,1);
                    HEX_HIGH: begin
                        if(hex_value==16) result(7,1);
                        else begin high_nibble<=hex_value[3:0]; position<=position+1'b1; state<=HEX_LOW; end
                    end
                    HEX_LOW: begin
                        if(hex_value==16) result(7,1);
                        else begin
                            pcm_arg0<=value0; pcm_arg1<={8'd0,high_nibble,hex_value[3:0]};
                            pcm_arg2<={14'd0,position==parse_length-1,block_bytes==0};
                            pcm_request<=1; state<=PCM_BYTE_WAIT;
                        end
                    end
                    PCM_BYTE_WAIT: if(pcm_done) begin
                        if(pcm_error!=0) result(pcm_error,1);
                        else if(position==parse_length-1) result(0,1);
                        else begin value0<=value0+1'b1; position<=position+1'b1; block_bytes<=block_bytes+1'b1; state<=HEX_HIGH; end
                    end
                    default: state<=COLLECT;
                endcase
            end
        end
    end
endmodule
