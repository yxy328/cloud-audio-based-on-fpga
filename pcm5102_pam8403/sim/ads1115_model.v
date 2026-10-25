`timescale 1ns/1ps
// Behavioral ADS1115 I2C slave for simulation only.
// Models the 16-bit register file, MSB-first transfers, the pointer register,
// address match and ACK/NACK. Conversion values come from the testbench via
// CODE; analog accuracy, PGA gain error and input impedance are not modelled.
module ads1115_model #(
    parameter [6:0] ADDR = 7'h48
)(
    input  wire        clk,
    input  wire        scl,
    inout  wire        sda,
    input  wire        present,
    input  wire [15:0] code
);
    reg [15:0] cfg;
    reg [1:0]  ptr;
    reg [7:0]  sh;
    reg [3:0]  bit;
    reg [3:0]  st;
    reg        match, rwbit, ack_phase, first_data, tx_started, released, byte_sel;
    reg        drive, dout;
    reg [15:0] rd_word;
    reg [7:0]  txb;
    reg        scl_q, sda_q;

    localparam [3:0] S_IDLE  = 4'd0,
                     S_ADDR  = 4'd1,
                     S_AACK  = 4'd2,
                     S_PTR   = 4'd3,
                     S_PACK  = 4'd4,
                     S_WDATA = 4'd5,
                     S_WACK  = 4'd6,
                     S_RDATA = 4'd7;

    // Explicit combinational blocks: a function call inside a continuous
    // assignment is only re-evaluated on its arguments by some simulators,
    // which would freeze the conversion value after the first read.
    reg [15:0] cur_word, next_word;
    always @* begin
        case (ptr)
            2'd0: cur_word = code;
            2'd1: cur_word = cfg;
            2'd2: cur_word = 16'h8000;
            default: cur_word = 16'h7FFF;
        endcase
        case (ptr + 1'b1)
            2'd0: next_word = code;
            2'd1: next_word = cfg;
            2'd2: next_word = 16'h8000;
            default: next_word = 16'h7FFF;
        endcase
    end

    assign sda = drive ? dout : 1'bz;

    always @(posedge clk) begin
        scl_q <= scl;
        sda_q <= sda;
    end

    wire scl_rise  = ~scl_q & scl;
    wire scl_fall  = scl_q & ~scl;
    wire start_det = scl_q & scl & sda_q & ~sda;
    wire stop_det  = scl_q & scl & ~sda_q & sda;

    initial begin
        cfg        = 16'h8583;
        ptr        = 2'd0;
        sh         = 8'd0;
        bit        = 4'd0;
        st         = S_IDLE;
        match      = 1'b0;
        rwbit      = 1'b0;
        ack_phase  = 1'b0;
        first_data = 1'b1;
        tx_started = 1'b0;
        released   = 1'b0;
        byte_sel   = 1'b0;
        drive      = 1'b0;
        dout       = 1'b0;
        rd_word    = 16'd0;
        txb        = 8'd0;
        scl_q      = 1'b1;
        sda_q      = 1'b1;
    end

    always @(posedge clk) begin
        if (start_det) begin
            st         <= S_ADDR;
            bit        <= 4'd0;
            sh         <= 8'd0;
            drive      <= 1'b0;
            tx_started <= 1'b0;
            released   <= 1'b0;
        end else if (stop_det) begin
            st         <= S_IDLE;
            drive      <= 1'b0;
            tx_started <= 1'b0;
            released   <= 1'b0;
        end else begin
            case (st)
            S_IDLE: ;

            S_ADDR: if (scl_rise) begin
                sh <= {sh[6:0], sda};
                if (bit == 4'd7) begin
                    match     <= present && (({sh[6:0], sda} >> 1) == ADDR);
                    rwbit     <= sda;
                    ack_phase <= 1'b0;
                    st        <= S_AACK;
                end else begin
                    bit <= bit + 1'b1;
                end
            end

            S_AACK: begin
                if (scl_fall && !ack_phase) begin
                    drive     <= match;
                    dout      <= 1'b0;
                    ack_phase <= 1'b1;
                end else if (scl_fall && ack_phase) begin
                    drive      <= 1'b0;
                    ack_phase  <= 1'b0;
                    bit        <= 4'd0;
                    sh         <= 8'd0;
                    first_data <= 1'b1;
                    if (!match) begin
                        st <= S_IDLE;
                    end else if (rwbit) begin
                        rd_word    <= cur_word;
                        txb        <= cur_word[15:8];
                        byte_sel   <= 1'b0;
                        // SCL is already low after the address ACK clock, so the
                        // first data bit is driven now instead of on a fall edge.
                        drive      <= 1'b1;
                        dout       <= cur_word[15];
                        bit        <= 4'd7;
                        tx_started <= 1'b1;
                        released   <= 1'b0;
                        st         <= S_RDATA;
                    end else begin
                        st <= S_PTR;
                    end
                end
            end

            S_PTR: if (scl_rise) begin
                sh <= {sh[6:0], sda};
                if (bit == 4'd7) begin
                    ack_phase <= 1'b0;
                    st        <= S_PACK;
                end else begin
                    bit <= bit + 1'b1;
                end
            end

            S_PACK: begin
                if (scl_fall && !ack_phase) begin
                    drive     <= 1'b1;
                    dout      <= 1'b0;
                    ack_phase <= 1'b1;
                end else if (scl_fall && ack_phase) begin
                    drive     <= 1'b0;
                    ack_phase <= 1'b0;
                    bit       <= 4'd0;
                    ptr       <= sh[1:0];
                    st        <= S_WDATA;
                end
            end

            S_WDATA: if (scl_rise) begin
                sh <= {sh[6:0], sda};
                if (bit == 4'd7) begin
                    ack_phase <= 1'b0;
                    st        <= S_WACK;
                end else begin
                    bit <= bit + 1'b1;
                end
            end

            S_WACK: begin
                if (scl_fall && !ack_phase) begin
                    drive     <= 1'b1;
                    dout      <= 1'b0;
                    ack_phase <= 1'b1;
                end else if (scl_fall && ack_phase) begin
                    drive     <= 1'b0;
                    ack_phase <= 1'b0;
                    bit       <= 4'd0;
                    st        <= S_WDATA;
                    if (ptr == 2'd1) begin
                        if (first_data) cfg[15:8] <= sh;
                        else            cfg[7:0]  <= sh;
                    end
                    first_data <= ~first_data;
                end
            end

            S_RDATA: begin
                if (scl_fall) begin
                    if (tx_started) begin
                        if (bit != 4'd0) begin
                            bit  <= bit - 1'b1;
                            dout <= txb[bit-1];
                        end else begin
                            drive    <= 1'b0;
                            released <= 1'b1;
                        end
                    end else begin
                        drive      <= 1'b1;
                        dout       <= txb[7];
                        bit        <= 4'd7;
                        tx_started <= 1'b1;
                    end
                end
                if (scl_rise && released) begin
                    released <= 1'b0;
                    if (sda) begin
                        st <= S_IDLE;
                    end else if (!byte_sel) begin
                        // Second byte of the same 16-bit register.
                        byte_sel   <= 1'b1;
                        tx_started <= 1'b0;
                        txb        <= rd_word[7:0];
                    end else begin
                        ptr        <= ptr + 1'b1;
                        rd_word    <= next_word;
                        txb        <= next_word[15:8];
                        byte_sel   <= 1'b0;
                        tx_started <= 1'b0;
                    end
                end
            end

            default: st <= S_IDLE;
            endcase
        end
    end

endmodule
