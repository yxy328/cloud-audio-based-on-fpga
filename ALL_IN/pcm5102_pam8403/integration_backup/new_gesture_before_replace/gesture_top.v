// ============================================================================
//  gesture_top.v —— APDS-9960 + OLED + eight-note five-timbre audio and vibrato (fix12)
//  手势接线: scl->H4 (J3 第23脚)  sda->G4 (J3 第24脚)，使用 2x20 排针。
//  clk->E2  tx->C3  led->L6；主工程入口为 top。
// ============================================================================

module gesture_top #(
    parameter [16:0] AUDIO_NOTE_FRAMES = 17'd14648,
    parameter [16:0] AUDIO_PIANO_FRAMES = 17'd58594,
    parameter [16:0] AUDIO_FLUTE_FRAMES = 17'd24414,
    parameter [16:0] AUDIO_UKULELE_FRAMES = 17'd34180,
    parameter [16:0] AUDIO_DRUM_FRAMES = 17'd19531,
    parameter AUDIO_VOLUME_SHIFT = 4,
    parameter [19:0] AUDIO_KEY_DEBOUNCE_CYCLES = 20'd1000000,
    parameter [25:0] AUDIO_LONG_PRESS_CYCLES = 26'd40000000
) (
    input  wire clk,
    input  wire key_s1, key_s2,
    inout  wire sda, scl,
    output wire tx, led,
    output wire i2s_bck, i2s_lrck, i2s_din
);

    // 上电复位 (100ms)
    reg [23:0] rst_cnt = 24'd0;
    reg        rst_n   = 1'b0;
    always @(posedge clk) begin
        if (rst_cnt < 24'd5_000_000) begin rst_cnt <= rst_cnt + 1'b1; rst_n <= 1'b0; end
        else rst_n <= 1'b1;
    end

    // 内部互连
    wire        i2c_start, i2c_rw, i2c_busy, i2c_done, i2c_nack, i2c_rvalid, gesture_valid, init_done;
    wire [6:0]  i2c_addr;
    wire [7:0]  i2c_reg, i2c_wdata, i2c_rdlen, i2c_rdata, raw_u, raw_d, raw_l, raw_r;
    wire [7:0]  dbg_gstatus, dbg_gflvl;
    wire [7:0]  dbg_id, dbg_enable, dbg_proximity, dbg_error;
    wire [7:0]  dbg_nack_count, dbg_nack_reg, dbg_gconf2, dbg_gpulse;
    wire [7:0]  dbg_peak;
    wire        dir_evaluated;
    wire [2:0]  start_dir, end_dir;

    wire bus_start, bus_rw, bus_done, bus_nack, bus_rvalid;
    wire [6:0] bus_addr;
    wire [7:0] bus_reg, bus_wdata, bus_rdlen;
    wire oled_start, oled_busy, oled_done, oled_nack;
    wire [7:0] oled_control, oled_data;
    wire [1:0] oled_status;
    wire note_bank, vibrato_enabled;
    wire [2:0] timbre_selected;

    i2c_bus_arbiter u_bus (
        .clk(clk), .rst_n(rst_n),
        .sensor_start(i2c_start), .sensor_rw(i2c_rw), .sensor_addr(i2c_addr),
        .sensor_reg(i2c_reg), .sensor_wdata(i2c_wdata), .sensor_rdlen(i2c_rdlen),
        .sensor_busy(i2c_busy), .sensor_done(i2c_done), .sensor_nack(i2c_nack),
        .sensor_rvalid(i2c_rvalid),
        .oled_start(oled_start), .oled_control(oled_control), .oled_data(oled_data),
        .oled_busy(oled_busy), .oled_done(oled_done), .oled_nack(oled_nack),
        .master_start(bus_start), .master_rw(bus_rw), .master_addr(bus_addr),
        .master_reg(bus_reg), .master_wdata(bus_wdata), .master_rdlen(bus_rdlen),
        .master_done(bus_done), .master_nack(bus_nack), .master_rvalid(bus_rvalid)
    );

    oled_display u_oled (
        .clk(clk), .rst_n(rst_n), .sensor_ready(init_done),
        .note_bank(note_bank), .timbre_selected(timbre_selected), .vibrato_enabled(vibrato_enabled),
        .gesture_valid(gesture_valid), .dir_evaluated(dir_evaluated),
        .start_dir(start_dir), .end_dir(end_dir),
        .cmd_start(oled_start), .cmd_control(oled_control), .cmd_data(oled_data),
        .cmd_busy(oled_busy), .cmd_done(oled_done), .cmd_nack(oled_nack),
        .status(oled_status)
    );

    gesture_audio #(.NOTE_FRAMES(AUDIO_NOTE_FRAMES), .PIANO_FRAMES(AUDIO_PIANO_FRAMES),
                    .FLUTE_FRAMES(AUDIO_FLUTE_FRAMES), .UKULELE_FRAMES(AUDIO_UKULELE_FRAMES),
                    .DRUM_FRAMES(AUDIO_DRUM_FRAMES), .VOLUME_SHIFT(AUDIO_VOLUME_SHIFT),
                    .KEY_DEBOUNCE_CYCLES(AUDIO_KEY_DEBOUNCE_CYCLES),
                    .LONG_PRESS_CYCLES(AUDIO_LONG_PRESS_CYCLES)) u_audio (
        .clk(clk), .resetn(rst_n), .sensor_ready(init_done),
        .gesture_valid(gesture_valid), .dir_evaluated(dir_evaluated),
        .start_dir(start_dir), .end_dir(end_dir), .key_s1(key_s1), .key_s2(key_s2),
        .note_bank(note_bank), .timbre_selected(timbre_selected), .vibrato_enabled(vibrato_enabled),
        .i2s_bck(i2s_bck), .i2s_lrck(i2s_lrck), .i2s_din(i2s_din)
    );

    // I2C 主机
    i2c_master #(.CLK_FREQ(50_000_000), .I2C_FREQ(100_000)) u_i2c (
        .clk(clk), .rst_n(rst_n),
        .cmd_start(bus_start), .cmd_addr(bus_addr), .cmd_reg(bus_reg),
        .cmd_rw(bus_rw), .cmd_wdata(bus_wdata), .cmd_rdlen(bus_rdlen),
        .busy(), .done(bus_done), .nack(bus_nack),
        .rdata(i2c_rdata), .rvalid(bus_rvalid), .scl(scl), .sda(sda)
    );

    // APDS-9960 控制
    apds9960_ctrl u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .i2c_start(i2c_start), .i2c_addr(i2c_addr), .i2c_reg(i2c_reg),
        .i2c_rw(i2c_rw), .i2c_wdata(i2c_wdata), .i2c_rdlen(i2c_rdlen),
        .i2c_busy(i2c_busy), .i2c_done(i2c_done), .i2c_nack(i2c_nack),
        .i2c_rdata(i2c_rdata), .i2c_rvalid(i2c_rvalid),
        .gesture_valid(gesture_valid),
        .raw_u(raw_u), .raw_d(raw_d), .raw_l(raw_l), .raw_r(raw_r),
        .start_dir(start_dir), .end_dir(end_dir),
        .init_done(init_done),
        .dbg_gstatus(dbg_gstatus), .dbg_gflvl(dbg_gflvl),
        .dbg_id(dbg_id), .dbg_enable(dbg_enable),
        .dbg_proximity(dbg_proximity), .dbg_error(dbg_error),
        .dbg_nack_count(dbg_nack_count), .dbg_nack_reg(dbg_nack_reg),
        .dbg_gconf2(dbg_gconf2), .dbg_gpulse(dbg_gpulse),
        .dbg_peak(dbg_peak), .dir_evaluated(dir_evaluated)
    );

    // UART 发送
    reg [7:0]  uart_byte;
    reg        uart_go;
    wire       uart_busy;

    uart_tx #(.CLK_FREQ(50_000_000), .BAUD(115200)) u_uart (
        .clk(clk), .rst_n(rst_n),
        .tx_data(uart_byte), .tx_start(uart_go), .tx_busy(uart_busy), .tx(tx)
    );

    // 消息类型
    localparam [2:0] MSG_BOOT=0, MSG_INIT_OK=1, MSG_NOSENSOR=2, MSG_HEARTBEAT=3, MSG_DATA=4, MSG_CONFIG=5;
    localparam [1:0] TS_IDLE=0, TS_LOAD=1, TS_BUSY=2, TS_DONE=3;

    reg [2:0]  msg_type;
    reg [1:0]  ts;
    reg [5:0]  char_idx;
    reg [7:0]  char_out;
    reg [5:0]  msg_len;
    reg [7:0]  lu, ld, ll, lr;
    reg [2:0]  lstart, lend;
    reg [7:0] lid, lenable, lstatus, llevel, lprox, lerror, lpeak;
    reg [7:0] lnack_count, lnack_reg, lgconf2, lgpulse;
    reg [1:0] loled_status;
    reg       lkind;
    reg pending_data;
    reg pending_tick;
    reg [7:0] pu, pd, pl, pr, ppeak;
    reg [2:0] pstart, pend;
    reg       pkind;
    reg        boot_sent, init_sent, config_sent;

    // 1秒心跳
    reg [25:0] tick_cnt;
    wire tick_pulse = (tick_cnt == 26'd50_000_000 - 1);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tick_cnt <= 26'd0;
        else if (tick_pulse) tick_cnt <= 26'd0;
        else tick_cnt <= tick_cnt + 1'b1;
    end

    // hex转ASCII
    function [7:0] hex2asc(input [3:0] h);
    begin
        if (h < 4'd10) hex2asc = 8'h30 + h;
        else hex2asc = 8'h41 + (h - 4'd10);
    end
    endfunction

    // 方向编码 -> 字符 (0=? 1=U 2=D 3=L 4=R)
    function [7:0] dir2char(input [2:0] d);
    begin
        case (d)
        3'd1: dir2char = "U";
        3'd2: dir2char = "D";
        3'd3: dir2char = "L";
        3'd4: dir2char = "R";
        default: dir2char = "?";
        endcase
    end
    endfunction

    // 字符生成
    always @(*) begin
        char_out = 8'h20;
        case (msg_type)
        MSG_BOOT:
            case (char_idx)
            0: char_out="A"; 1: char_out="P"; 2: char_out="D"; 3: char_out="S";
            4: char_out="9"; 5: char_out="9"; 6: char_out="6"; 7: char_out="0";
            8: char_out=" "; 9: char_out="f"; 10: char_out="i"; 11: char_out="x";
            12: char_out="1"; 13: char_out="2"; 14: char_out=8'h0D; 15: char_out=8'h0A;
            default: char_out=" ";
            endcase
        MSG_INIT_OK:
            case (char_idx)
            0: char_out="i"; 1: char_out="n"; 2: char_out="i"; 3: char_out="t";
            4: char_out=" "; 5: char_out="O"; 6: char_out="K";
            7: char_out=8'h0D; 8: char_out=8'h0A;
            default: char_out=" ";
            endcase
        MSG_NOSENSOR:
            case (char_idx)
            0: char_out="W"; 1: char_out="A"; 2: char_out="I"; 3: char_out="T";
            4: char_out=" "; 5: char_out="I"; 6: char_out="D"; 7: char_out="=";
            8: char_out=hex2asc(lid[7:4]); 9: char_out=hex2asc(lid[3:0]);
            10: char_out=" "; 11: char_out="E"; 12: char_out="R"; 13: char_out="=";
            14: char_out=hex2asc(lerror[7:4]); 15: char_out=hex2asc(lerror[3:0]);
            16: char_out=" "; 17: char_out="N"; 18: char_out="C"; 19: char_out="=";
            20: char_out=hex2asc(lnack_count[7:4]); 21: char_out=hex2asc(lnack_count[3:0]);
            22: char_out=" "; 23: char_out="N"; 24: char_out="R"; 25: char_out="=";
            26: char_out=hex2asc(lnack_reg[7:4]); 27: char_out=hex2asc(lnack_reg[3:0]);
            28: char_out=8'h0D; 29: char_out=8'h0A;
            default: char_out=" ";
            endcase
        MSG_CONFIG: // Actual register readbacks: "CFG GC=xx GP=xx\r\n"
            case (char_idx)
            0: char_out="C"; 1: char_out="F"; 2: char_out="G"; 3: char_out=" ";
            4: char_out="G"; 5: char_out="C"; 6: char_out="=";
            7: char_out=hex2asc(lgconf2[7:4]); 8: char_out=hex2asc(lgconf2[3:0]);
            9: char_out=" "; 10: char_out="G"; 11: char_out="P"; 12: char_out="=";
            13: char_out=hex2asc(lgpulse[7:4]); 14: char_out=hex2asc(lgpulse[3:0]);
            15: char_out=8'h0D; 16: char_out=8'h0A;
            default: char_out=" ";
            endcase
        MSG_HEARTBEAT:  // "ID=xx EN=xx ST=xx FL=xx P=xx PK=xx ER=xx NC=xx NR=xx OD=xx\r\n"
            case (char_idx)
            0: char_out="I"; 1: char_out="D"; 2: char_out="=";
            3: char_out=hex2asc(lid[7:4]); 4: char_out=hex2asc(lid[3:0]);
            5: char_out=" "; 6: char_out="E"; 7: char_out="N"; 8: char_out="=";
            9: char_out=hex2asc(lenable[7:4]); 10: char_out=hex2asc(lenable[3:0]);
            11: char_out=" "; 12: char_out="S"; 13: char_out="T"; 14: char_out="=";
            15: char_out=hex2asc(lstatus[7:4]); 16: char_out=hex2asc(lstatus[3:0]);
            17: char_out=" "; 18: char_out="F"; 19: char_out="L"; 20: char_out="=";
            21: char_out=hex2asc(llevel[7:4]); 22: char_out=hex2asc(llevel[3:0]);
            23: char_out=" "; 24: char_out="P"; 25: char_out="=";
            26: char_out=hex2asc(lprox[7:4]); 27: char_out=hex2asc(lprox[3:0]);
            28: char_out=" "; 29: char_out="P"; 30: char_out="K"; 31: char_out="=";
            32: char_out=hex2asc(lpeak[7:4]); 33: char_out=hex2asc(lpeak[3:0]);
            34: char_out=" "; 35: char_out="E"; 36: char_out="R"; 37: char_out="=";
            38: char_out=hex2asc(lerror[7:4]); 39: char_out=hex2asc(lerror[3:0]);
            40: char_out=" "; 41: char_out="N"; 42: char_out="C"; 43: char_out="=";
            44: char_out=hex2asc(lnack_count[7:4]); 45: char_out=hex2asc(lnack_count[3:0]);
            46: char_out=" "; 47: char_out="N"; 48: char_out="R"; 49: char_out="=";
            50: char_out=hex2asc(lnack_reg[7:4]); 51: char_out=hex2asc(lnack_reg[3:0]);
            52: char_out=" "; 53: char_out="O"; 54: char_out="D"; 55: char_out="=";
            56: char_out="0"; 57: char_out=hex2asc({2'b00,loled_status});
            58: char_out=8'h0D; 59: char_out=8'h0A;
            default: char_out=" ";
            endcase
        default:  // MSG_DATA: "S ?>? U=xx D=xx L=xx R=xx K=xx\r\n" 32字符
                  // 首字符 S=采样(方向未判定) G=方向判定结果
            case (char_idx)
            0: char_out=lkind ? "G" : "S";
            1: char_out=" ";
            2: char_out=dir2char(lstart);
            3: char_out=">";
            4: char_out=dir2char(lend);
            5: char_out=" ";
            6: char_out="U"; 7: char_out="=";
            8: char_out=hex2asc(lu[7:4]); 9: char_out=hex2asc(lu[3:0]);
            10: char_out=" "; 11: char_out="D"; 12: char_out="=";
            13: char_out=hex2asc(ld[7:4]); 14: char_out=hex2asc(ld[3:0]);
            15: char_out=" "; 16: char_out="L"; 17: char_out="=";
            18: char_out=hex2asc(ll[7:4]); 19: char_out=hex2asc(ll[3:0]);
            20: char_out=" "; 21: char_out="R"; 22: char_out="=";
            23: char_out=hex2asc(lr[7:4]); 24: char_out=hex2asc(lr[3:0]);
            25: char_out=" "; 26: char_out="K"; 27: char_out="=";
            28: char_out=hex2asc(lpeak[7:4]); 29: char_out=hex2asc(lpeak[3:0]);
            30: char_out=8'h0D; 31: char_out=8'h0A;
            default: char_out=" ";
            endcase
        endcase
    end

    // 消息长度
    always @(*) begin
        case (msg_type)
        MSG_BOOT: msg_len = 6'd16;
        MSG_INIT_OK: msg_len = 6'd9;
        MSG_NOSENSOR: msg_len = 6'd30;
        MSG_HEARTBEAT: msg_len = 6'd60;
        MSG_CONFIG: msg_len = 6'd17;
        default: msg_len = 6'd32;
        endcase
    end

    // 发送控制
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ts <= TS_IDLE; char_idx <= 6'd0; uart_byte <= 8'd0; uart_go <= 1'b0;
            msg_type <= MSG_BOOT; lu <= 8'd0; ld <= 8'd0; ll <= 8'd0; lr <= 8'd0;
            lstart <= 3'd0; lend <= 3'd0;
            lid <= 0; lenable <= 0; lstatus <= 0; llevel <= 0; lprox <= 0; lerror <= 0;
            lpeak <= 0; lkind <= 0;
            lnack_count <= 0; lnack_reg <= 0; lgconf2 <= 0; lgpulse <= 0;
            loled_status <= 0;
            pending_data <= 0; pending_tick <= 0;
            pu <= 0; pd <= 0; pl <= 0; pr <= 0; pstart <= 0; pend <= 0;
            ppeak <= 0; pkind <= 0;
            boot_sent <= 1'b0; init_sent <= 1'b0; config_sent <= 1'b0;
        end else begin
            uart_go <= 1'b0;
            // Retain a new sample or completed gesture while UART is sending.
            if (gesture_valid) begin
                pending_data <= 1;
                pu <= raw_u; pd <= raw_d; pl <= raw_l; pr <= raw_r;
                pstart <= start_dir; pend <= end_dir;
                ppeak <= dbg_peak; pkind <= dir_evaluated;
            end
            if (tick_pulse) pending_tick <= 1;
            case (ts)
            TS_IDLE: begin
                if (!boot_sent) begin
                    boot_sent <= 1'b1; msg_type <= MSG_BOOT; char_idx <= 6'd0; ts <= TS_LOAD;
                end else if (!init_sent && init_done) begin
                    init_sent <= 1'b1; msg_type <= MSG_INIT_OK; char_idx <= 6'd0; ts <= TS_LOAD;
                end else if (!config_sent && init_done) begin
                    config_sent <= 1'b1; lgconf2 <= dbg_gconf2; lgpulse <= dbg_gpulse;
                    msg_type <= MSG_CONFIG; char_idx <= 6'd0; ts <= TS_LOAD;
                end else if (pending_tick) begin
                    pending_tick <= tick_pulse;
                    lid <= dbg_id; lenable <= dbg_enable;
                    lstatus <= dbg_gstatus; llevel <= dbg_gflvl;
                    lprox <= dbg_proximity; lerror <= dbg_error;
                    lpeak <= dbg_peak;
                    lnack_count <= dbg_nack_count; lnack_reg <= dbg_nack_reg;
                    loled_status <= oled_status;
                    msg_type <= init_done ? MSG_HEARTBEAT : MSG_NOSENSOR;
                    char_idx <= 6'd0; ts <= TS_LOAD;
                end else if (pending_data) begin
                    lu <= pu; ld <= pd; ll <= pl; lr <= pr;
                    lstart <= pstart; lend <= pend;
                    lkind <= pkind; lpeak <= ppeak;
                    pending_data <= gesture_valid;
                    msg_type <= MSG_DATA; char_idx <= 6'd0; ts <= TS_LOAD;
                end
            end
            TS_LOAD: begin
                uart_byte <= char_out; uart_go <= 1'b1;
                char_idx <= char_idx + 1'b1; ts <= TS_BUSY;
            end
            TS_BUSY: begin
                if (uart_busy) ts <= TS_DONE;
            end
            TS_DONE: begin
                if (!uart_busy) begin
                    if (char_idx == msg_len) ts <= TS_IDLE;
                    else ts <= TS_LOAD;
                end
            end
            default: ts <= TS_IDLE;
            endcase
        end
    end

    assign led = init_done;

endmodule
