`timescale 1ns/1ps
module tb_ttp229_modes;
    reg clk = 0;
    always #500 clk = ~clk; // 1MHz, real us/ms timings.
    wire [2:0] done;
    mode_button_checker button (.clk(clk), .done(done[0]));
    dynamic_serial_checker #(.ACTIVE_LOW(1)) low (.clk(clk), .done(done[1]));
    dynamic_serial_checker #(.ACTIVE_LOW(0)) high (.clk(clk), .done(done[2]));
    initial begin
        wait (&done);
        $display("PASS: S2 debounce/toggle/hold/release, dynamic 8/16 frames, abort/rearm and cold-start preservation");
        $finish;
    end
    initial begin
        #850_000_000;
        $fatal(1, "Mode selection test timed out");
    end
endmodule

module mode_button_checker(input wire clk, output reg done = 0);
    reg resetn = 0, s2 = 0;
    wire toggled, level_mode, changed, level_changed;
    ttp229_mode_select #(.CLK_FREQ(1_000_000), .TOGGLE_MODE(1)) toggle (
        .clk(clk), .resetn(resetn), .s2(s2), .mode_16(toggled),
        .mode_changed(changed), .state_o()
    );
    ttp229_mode_select #(.CLK_FREQ(1_000_000)) level (
        .clk(clk), .resetn(resetn), .s2(s2), .mode_16(level_mode),
        .mode_changed(level_changed), .state_o()
    );
    integer events = 0;
    reg previous_changed = 0;
    always @(posedge clk) begin
        #1;
        if (changed && previous_changed) $fatal(1, "Mode event wider than one clock");
        if (changed) events = events + 1;
        previous_changed = changed;
    end
    task drive;
        input value;
        input integer ticks;
        begin
            @(negedge clk); s2 = value;
            repeat (ticks) @(negedge clk);
        end
    endtask
    initial begin
        repeat (5) @(negedge clk);
        resetn = 1;
        drive(1, 19000);
        if (toggled || level_mode || events) $fatal(1, "19ms bounce was accepted");
        drive(0, 10);
        drive(1, 20001);
        if (toggled || level_mode) $fatal(1, "Missing two-stage S2 synchronization");
        repeat (4) @(negedge clk);
        if (!toggled || !level_mode || events != 1) $fatal(1, "20ms press did not select 16 keys");
        drive(1, 50000);
        if (!toggled || events != 1) $fatal(1, "Long hold repeated a toggle");
        drive(0, 19000);
        drive(1, 25000);
        if (!toggled || events != 1) $fatal(1, "Unconfirmed release rearmed press");
        drive(0, 20005);
        if (!toggled || level_mode || events != 1) $fatal(1, "Release changed retained toggle mode");
        drive(1, 20005);
        if (toggled || !level_mode || events != 2) $fatal(1, "Second press did not select 8 keys");
        @(negedge clk); resetn = 0;
        repeat (3) @(negedge clk);
        if (toggled || level_mode) $fatal(1, "Reset did not select 8 keys");
        done = 1;
        $display("PASS: real 20ms S2 debounce, bounce rejection, one toggle per held press, retained release and optional level mode");
    end
endmodule

module dynamic_serial_checker #(parameter ACTIVE_LOW = 1)
    (input wire clk, output reg done = 0);
    localparam IDLE = ACTIVE_LOW ? 1'b1 : 1'b0;
    reg resetn = 0, mode_16 = 0;
    reg [15:0] pads = 16'h0081;
    reg sdo = IDLE;
    wire scl, valid;
    wire [15:0] keys;
    wire [2:0] state;
    wire [3:0] bit_count;
    // Default 600ms startup must survive mode changes before the first read.
    ttp229_ctrl #(.CLK_FREQ(1_000_000), .DYNAMIC_MODE(1), .TP_ACTIVE_LOW(ACTIVE_LOW)) dut (
        .clk(clk), .resetn(resetn), .sdo(sdo), .scl(scl),
        .touch_valid(valid), .touch_keys(keys), .state_o(state), .bit_cnt_o(bit_count),
        .mode_16(mode_16), .enable(1'b1)
    );
    integer index = 0, frame_edges = 0;
    reg [15:0] frame_pads;
    time last_edge = 0, release_time, rearm_time;
    reg [15:0] expected;
    reg check_frames = 1;
    always @(scl) begin
        if (scl === 0 || scl === 1) begin
            if ($time - last_edge > 2_000_000) begin
                index = 0;
                frame_edges = 0;
                frame_pads = pads;
            end
            last_edge = $time;
            if (scl != IDLE) begin
                frame_edges = frame_edges + 1;
                if (index < (mode_16 ? 16 : 8)) begin
                    sdo <= #100 (ACTIVE_LOW ? ~frame_pads[index] : frame_pads[index]);
                    index = index + 1;
                end
            end
        end
    end
    always @(posedge valid) begin
        #1;
        if (check_frames) begin
            expected = mode_16 ? frame_pads : {8'd0, frame_pads[7:0]};
            if (frame_edges != (mode_16 ? 16 : 8) || keys !== expected)
                $fatal(1, "Frame active_low=%0d mode=%0d edges=%0d keys=%h expected=%h",
                       ACTIVE_LOW, mode_16, frame_edges, keys, expected);
        end
    end
    task next_frame;
        input [15:0] new_pads;
        begin
            @(negedge valid);
            @(negedge clk); pads = new_pads;
            @(posedge valid); #2;
            if (keys !== (mode_16 ? new_pads : {8'd0, new_pads[7:0]}))
                $fatal(1, "Key order or stale upper bits in mode=%0d", mode_16);
        end
    endtask
    task switch_during_frame;
        input new_mode;
        input [15:0] new_pads;
        begin
            wait (state == 1 && bit_count == 3 && dut.timer > 10);
            @(negedge clk);
            mode_16 = new_mode;
            pads = new_pads;
            rearm_time = $time;
            @(negedge clk);
            if (keys !== 0 || valid || scl !== IDLE || state !== 3)
                $fatal(1, "Mid-frame mode switch failed to discard partial frame");
            repeat (2999) begin
                @(negedge clk);
                if (scl !== IDLE || valid) $fatal(1, "Rearm quiet time shorter than 3ms");
            end
            @(posedge valid); #2;
            if (keys !== new_pads || $time - rearm_time < 3_000_000)
                $fatal(1, "First frame after rearm is not aligned to K1");
        end
    endtask
    integer key;
    initial begin
        repeat (5) @(negedge clk);
        resetn = 1; release_time = $time;
        #20_000_000;
        @(negedge clk); mode_16 = 1;
        #20_000_000;
        @(negedge clk); mode_16 = 0;
        wait (scl != IDLE);
        if ($time - release_time < 599_999_000) $fatal(1, "Mode change shortened 600ms startup");
        @(posedge valid); #2;
        if (keys !== 16'h0081) $fatal(1, "First 8-key frame lost K1/K8");
        switch_during_frame(1, 16'h8001);
        for (key = 0; key < 16; key = key + 1) next_frame(16'h0001 << key);
        next_frame(16'hffff);
        switch_during_frame(0, 16'h0081);
        for (key = 0; key < 8; key = key + 1) next_frame(16'h0001 << key);
        done = 1;
        $display("PASS: dynamic serial polarity=%0d, all 8/16 key positions, 600ms startup and bidirectional mid-frame abort/rearm", ACTIVE_LOW);
    end
endmodule
