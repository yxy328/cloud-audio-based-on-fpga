`timescale 1ns/1ps
// Physical active-low chip model: K1 first, no FPGA reset connection.
module tb_touch_live;
    reg clk = 1'b0;
    reg user_key = 1'b0; // Holding S1 must not stop the diagnostic.
    reg sdo = 1'b1;
    wire scl;
    reg [15:0] module_keys = 16'h0001;
    reg [15:0] module_frame = 16'h0000;
    reg module_level = 1'b1;
    integer module_index = 0;
    time last_module_edge = 0;
    time first_fall = 0;
    time last_fall = 0;
    integer falls = 0;
    integer completed_frames = 0;

    always #10 clk = ~clk;
    // Only shorten the already independently tested 600 ms startup.
    TOP_TOUCH_LIVE #(.TTP_STARTUP_US(3000)) dut (
        .CLK_IN(clk), .USER_KEY(user_key), .touch_scl(scl), .touch_sdo(sdo)
    );

    always @(scl) begin
        if (scl === 1'b0 || scl === 1'b1) begin
            if ($time - last_module_edge > 2_000_000) begin
                module_index = 0;
                module_level = 1'b1;
            end
            last_module_edge = $time;
            if (scl === 1'b0 && module_index < 16) begin
                if (module_index == 0)
                    module_frame = module_keys;
                module_level = ~module_frame[module_index];
                module_index = module_index + 1;
            end
            #37;
            sdo = module_level;
        end
    end

    always @(negedge scl) begin
        if (falls == 0)
            first_fall = $time;
        else if ($time - last_fall != 20_000)
            $fatal(1, "SCL period is not 20 us");
        last_fall = $time;
        falls = falls + 1;
        #100;
        if (falls == 1 && (dut.frame_start !== 1'b1 ||
            dut.state_o !== 3'd1 || dut.bit_cnt_o !== 4'd0))
            $fatal(1, "frame_start did not mark the first low pulse");
        if (falls == 1 && completed_frames == 0 && sdo !== 1'b0)
            $fatal(1, "K1 did not produce low SDO during the first bit");
    end

    always @(posedge dut.live_probe[0]) begin
        #1;
        if ($time - first_fall != 11 || dut.live_probe[12] !== 1'b0 ||
            dut.live_probe[7:5] !== 3'd1 || dut.live_probe[4:1] !== 4'd0)
            $fatal(1, "GAO snapshot trigger does not mark bit 0 at +10 ns");
    end

    always @(posedge dut.touch_valid) begin
        #1;
        if (falls != 16 || module_index != 16)
            $fatal(1, "Frame did not contain exactly 16 physical clock pulses");
        if ($time - first_fall != 310_001)
            $fatal(1, "Frame did not complete 310 us after the first falling edge");
        if (dut.frame_start !== 1'b0 || scl !== 1'b1 ||
            dut.state_o !== 3'd2 || dut.bit_cnt_o !== 4'd0)
            $fatal(1, "Frame completion state is incorrect");
        if (dut.touch_keys !== ((completed_frames == 0) ? 16'h0001 : 16'h0000))
            $fatal(1, "Wrong key result: %h", dut.touch_keys);
        #10;
        if (dut.live_probe[28:13] !== ((completed_frames == 0) ? 16'h0001 : 16'h0000) ||
            dut.live_probe[10] !== 1'b1 || dut.live_probe[8] !== 1'b1)
            $fatal(1, "GAO snapshot missed the completed key frame");
        completed_frames = completed_frames + 1;
        if (completed_frames == 2) begin
            $display("PASS: live diagnostic at 50 MHz, S1 held low, K1 0001 then released 0000, 16 pulses, 310 us frame fits the 325.12 us GAO post-trigger window");
            $finish;
        end
        module_keys = 16'h0000;
        user_key = 1'b1;
        falls = 0;
    end

    initial begin
        #10_000_000;
        $fatal(1, "Live diagnostic simulation timed out");
    end
endmodule
