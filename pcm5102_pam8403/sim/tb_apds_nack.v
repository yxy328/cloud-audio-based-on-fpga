`timescale 1ns/1ps
// Real controller/master over an undriven, pulled-up bus: absent sensor.
module tb_apds_nack;
    reg clk=0, resetn=0;
    always #10 clk=~clk;
    tri1 scl, sda;
    wire start, rw, busy, done, nack, rvalid, ready, valid, evaluated;
    wire [6:0] address;
    wire [7:0] register_address, wdata, rdlen, rdata, error, nack_count;
    wire [2:0] start_dir, end_dir;
    i2c_master master (
        .clk(clk), .rst_n(resetn), .cmd_start(start), .cmd_addr(address),
        .cmd_reg(register_address), .cmd_rw(rw), .cmd_wdata(wdata), .cmd_rdlen(rdlen),
        .busy(busy), .done(done), .nack(nack), .rdata(rdata), .rvalid(rvalid),
        .scl(scl), .sda(sda)
    );
    apds9960_ctrl #(.DELAY_INIT(4), .DELAY_POLL(4), .DELAY_ACTIVE(4)) controller (
        .clk(clk), .rst_n(resetn), .i2c_start(start), .i2c_addr(address),
        .i2c_reg(register_address), .i2c_rw(rw), .i2c_wdata(wdata), .i2c_rdlen(rdlen),
        .i2c_busy(busy), .i2c_done(done), .i2c_nack(nack), .i2c_rdata(rdata), .i2c_rvalid(rvalid),
        .gesture_valid(valid), .dir_evaluated(evaluated), .init_done(ready),
        .start_dir(start_dir), .end_dir(end_dir), .dbg_error(error), .dbg_nack_count(nack_count),
        .raw_u(), .raw_d(), .raw_l(), .raw_r(), .dbg_peak(), .dbg_gstatus(), .dbg_gflvl(),
        .dbg_id(), .dbg_enable(), .dbg_proximity(), .dbg_nack_reg(), .dbg_gconf2(), .dbg_gpulse()
    );
    integer failed_commands=0;
    always @(posedge clk) begin
        if (resetn) begin
            if (ready || valid || evaluated || start_dir || end_dir || rvalid)
                $fatal(1,"Absent/NACKing APDS produced ready, direction or gesture data");
            if (done) begin
                if (!nack) $fatal(1,"Absent APDS was falsely ACKed");
                failed_commands=failed_commands+1;
            end
        end
    end
    initial begin
        repeat(4) @(negedge clk); resetn=1;
        wait(failed_commands==3);
        repeat(6) @(negedge clk);
        if (nack_count !== 3 || !(error & 8'h01))
            $fatal(1,"APDS failed to count and report NACK retries");
        $display("PASS: absent APDS retries initialization, records NACK and emits no false gesture");
        $finish;
    end
    initial begin #1000000; $fatal(1,"APDS NACK retry timeout"); end
endmodule
