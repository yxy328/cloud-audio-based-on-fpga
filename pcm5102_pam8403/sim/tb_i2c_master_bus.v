`timescale 1ns/1ps
// Pin-level slave: no DUT state injection. Real 50MHz/100kHz bus timing.
module tb_i2c_master_bus;
    reg clk=0, resetn=0, cmd_start=0, cmd_rw=0;
    reg [7:0] cmd_reg=8'hA3, cmd_wdata=8'h29, cmd_rdlen=0;
    wire busy, done, nack, rvalid;
    wire [7:0] rdata;
    tri1 scl, sda;
    reg slave_low=0;
    assign sda=slave_low ? 1'b0 : 1'bz;
    always #10 clk=~clk;
    i2c_master dut (
        .clk(clk), .rst_n(resetn), .cmd_start(cmd_start), .cmd_addr(7'h39),
        .cmd_reg(cmd_reg), .cmd_rw(cmd_rw), .cmd_wdata(cmd_wdata),
        .cmd_wdata1(8'h00), .cmd_wlen(1'b0),
        .cmd_rdlen(cmd_rdlen), .busy(busy), .done(done), .nack(nack),
        .rdata(rdata), .rvalid(rvalid), .scl(scl), .sda(sda)
    );
    integer received=0, done_count=0;
    reg [7:0] read_bytes [0:1];
    always @(posedge clk) begin
        if (resetn && rvalid) begin
            if (received > 1) $fatal(1,"Unexpected extra read-valid pulse");
            read_bytes[received]=rdata;
            received=received+1;
        end
        if (resetn && done) done_count=done_count+1;
    end
    task wait_start;
        begin
            @(negedge sda);
            while (scl !== 1'b1) @(negedge sda);
        end
    endtask
    task wait_stop;
        begin
            @(posedge sda);
            while (scl !== 1'b1) @(posedge sda);
        end
    endtask
    task receive_byte;
        input [7:0] expected;
        input acknowledge;
        reg [7:0] value;
        integer bit_number;
        begin
            value=0;
            for (bit_number=7; bit_number>=0; bit_number=bit_number-1) begin
                @(posedge scl); value[bit_number]=sda;
            end
            if (value !== expected)
                $fatal(1,"I2C transmitted %02x, expected %02x",value,expected);
            @(negedge scl); slave_low=acknowledge;
            @(posedge scl);
            @(negedge scl); slave_low=0;
        end
    endtask
    task send_byte;
        input [7:0] value;
        input expected_nack;
        integer bit_number;
        begin
            for (bit_number=7; bit_number>=0; bit_number=bit_number-1) begin
                slave_low=~value[bit_number];
                @(posedge scl);
                @(negedge scl);
            end
            slave_low=0;
            @(posedge scl);
            if (sda !== expected_nack)
                $fatal(1,"I2C master ACK/NACK mismatch: %b expected %b",sda,expected_nack);
            @(negedge scl);
        end
    endtask
    reg slave_finished=0;
    initial begin
        // Initialization register write, including all slave ACKs.
        wait_start;
        receive_byte(8'h72,1);
        receive_byte(8'hA3,1);
        receive_byte(8'h29,1);
        wait_stop;
        // Register-address write followed by repeated start and two-byte read.
        wait_start;
        receive_byte(8'h72,1);
        receive_byte(8'h92,1);
        wait_start;
        receive_byte(8'h73,1);
        send_byte(8'h96,0);
        send_byte(8'h5A,1);
        wait_stop;
        // An absent slave leaves address ACK high; no read may be emitted.
        wait_start;
        receive_byte(8'h72,0);
        wait_stop;
        slave_finished=1;
    end
    task command;
        input read_mode;
        input [7:0] address_reg;
        input [7:0] length;
        input expected_nack;
        begin
            @(negedge clk);
            cmd_rw=read_mode; cmd_reg=address_reg; cmd_rdlen=length; cmd_start=1;
            @(negedge clk); cmd_start=0;
            if (!busy) $fatal(1,"I2C did not accept command");
            wait(done);
            if (nack !== expected_nack || busy)
                $fatal(1,"I2C completion/NACK mismatch");
            repeat(4) @(negedge clk);
            if (done) $fatal(1,"I2C done must be a one-clock pulse");
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); resetn=1;
        command(0,8'hA3,0,0);
        if (received) $fatal(1,"Write transaction emitted read data");
        command(1,8'h92,2,0);
        if (received !== 2 || read_bytes[0] !== 8'h96 || read_bytes[1] !== 8'h5A)
            $fatal(1,"SDA synchronized multi-byte read mismatch");
        command(1,8'hAF,1,1);
        if (received !== 2 || done_count !== 3 || !slave_finished)
            $fatal(1,"NACK emitted data or failed to complete/STOP");
        if (scl !== 1'b1 || sda !== 1'b1)
            $fatal(1,"I2C failed to release bus after STOP");
        $display("PASS: pin-level I2C write ACK, repeated-start two-byte read, master ACK/NACK, absent-slave NACK and bus release");
        $finish;
    end
    initial begin #2000000; $fatal(1,"I2C pin-level test timeout"); end
endmodule
