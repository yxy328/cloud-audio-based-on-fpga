`timescale 1ns/1ps

// Model the official pROM READ_MODE=0: the addressed pixel becomes valid
// after one rising edge. HUB75 samples RGB on the same hub_CK rising edge,
// so the scanner must prepare each pixel one scan clock in advance.
module tb_hub75e_scan;
    reg clk = 1'b0;
    reg clock_run = 1'b0;
    reg resetn = 1'b0;
    always begin
        #20;
        if (clock_run)
            clk = ~clk;
        else
            clk = 1'b0;
    end

    wire [4:0] rows;
    wire hub_ck, hub_st, hub_oe, frame_clk;
    wire [10:0] ram_addr;
    reg [10:0] rom_pixel;
    integer failures = 0;
    integer shift_count = 0;
    integer row_latches = 0;
    integer frame_edges = 0;
    integer row_cycles = 0;
    integer last_latch_cycle = 0;
    integer previous_latch = 0;
    integer expected_pixel;
    integer expected_row;
    reg [4:0] displayed_row;
    reg display_seen = 1'b0;
    reg latched_this_row = 1'b0;

    hub75e_if dut (
        .clk(clk), .resetn(resetn), .rows(rows), .hub_ck(hub_ck),
        .hub_st(hub_st), .hub_oe(hub_oe), .ram_addr(ram_addr),
        .frame_clk(frame_clk)
    );

    always @(posedge clk) begin
        if (!resetn)
            rom_pixel <= 11'd0;
        else begin
            rom_pixel <= ram_addr;
            row_cycles = row_cycles + 1;
        end
    end

    // Outside SHIFT, every rising scan clock belongs to the blank/latch
    // interval. Checking after settling also covers reset with clk high.
    always @(posedge clk) begin
        #1;
        if (hub_ck === 1'b0 && hub_oe !== 1'b1) begin
            if (failures < 12)
                $display("FAIL: panel was enabled during blank/prime/LAT");
            failures = failures + 1;
        end
        if (!resetn && (hub_ck !== 1'b0 || hub_st !== 1'b0)) begin
            $display("FAIL: output clocks active while reset asserted");
            failures = failures + 1;
        end
    end

    // The data used here is the previous ROM read, before its NBA update.
    always @(posedge hub_ck) begin
        if (resetn) begin
            expected_pixel = ((row_latches % 32) * 64) + shift_count;
            if (rom_pixel !== expected_pixel[10:0]) begin
                if (failures < 12)
                    $display("FAIL: row=%0d col=%0d shifted pixel=%h expected=%h",
                             row_latches % 32, shift_count, rom_pixel,
                             expected_pixel[10:0]);
                failures = failures + 1;
            end
            if (hub_st !== 1'b0 || frame_clk !== 1'b0) begin
                $display("FAIL: CK overlaps LAT/frame marker");
                failures = failures + 1;
            end
            if (display_seen && rows !== displayed_row) begin
                $display("FAIL: display row changed during pixel shifting");
                failures = failures + 1;
            end
            shift_count = shift_count + 1;
        end
    end

    always @(posedge frame_clk) begin
        if (resetn)
            frame_edges = frame_edges + 1;
    end

    always @(posedge hub_st) begin
        if (resetn) begin
            expected_row = row_latches % 32;
            if (shift_count != 64) begin
                if (failures < 12)
                    $display("FAIL: row %0d had %0d shift clocks, expected 64",
                             expected_row, shift_count);
                failures = failures + 1;
            end
            if (hub_oe !== 1'b1 || hub_ck !== 1'b0 ||
                frame_clk !== 1'b1 || rows !== expected_row[4:0]) begin
                if (failures < 12)
                    $display("FAIL: latch signals OE=%b CK=%b frame=%b row=%0d/%0d",
                             hub_oe, hub_ck, frame_clk, rows, expected_row);
                failures = failures + 1;
            end
            if (frame_edges != row_latches + 1) begin
                if (failures < 12)
                    $display("FAIL: row latch marker did not occur exactly once");
                failures = failures + 1;
            end
            if (previous_latch && row_cycles - last_latch_cycle != 67) begin
                if (failures < 12)
                    $display("FAIL: row period %0d scan clocks, expected 67",
                             row_cycles - last_latch_cycle);
                failures = failures + 1;
            end
            displayed_row = rows;
            display_seen = 1'b1;
            latched_this_row = 1'b1;
            row_latches = row_latches + 1;
            shift_count = 0;
            previous_latch = 1;
            last_latch_cycle = row_cycles;
        end
    end

    always @(negedge hub_oe) begin
        if (resetn && !latched_this_row) begin
            $display("FAIL: display enabled before any complete row was latched");
            failures = failures + 1;
        end
    end

    task clear_observers;
        begin
            shift_count = 0;
            row_latches = 0;
            frame_edges = 0;
            row_cycles = 0;
            last_latch_cycle = 0;
            previous_latch = 0;
            display_seen = 1'b0;
            latched_this_row = 1'b0;
        end
    endtask

    task check_reset;
        begin
            if (ram_addr !== 11'd0 || rows !== 5'd0 ||
                hub_ck !== 1'b0 || hub_st !== 1'b0 ||
                hub_oe !== 1'b1 || frame_clk !== 1'b0) begin
                $display("FAIL: reset while clock stopped: ad=%h row=%h CK=%b LAT=%b OE=%b frame=%b",
                         ram_addr, rows, hub_ck, hub_st, hub_oe, frame_clk);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        // TOP holds its divided clock at zero throughout power-on reset.
        // There is intentionally no 1 -> 0 reset edge at startup.
        #100;
        check_reset;
        clear_observers;
        resetn = 1'b1;
        clock_run = 1'b1;
        wait (row_latches >= 34);

        // Stop low, assert and release reset without giving the scanner
        // a clock edge. Then require a fresh coherent row-zero startup.
        @(negedge clk);
        clock_run = 1'b0;
        #1;
        resetn = 1'b0;
        #99;
        check_reset;
        clear_observers;
        resetn = 1'b1;
        clock_run = 1'b1;
        wait (row_latches >= 34);

        // User reset interrupts a scan while the clock keeps running.
        wait (shift_count == 19);
        #1;
        resetn = 1'b0;
        #1;
        check_reset;
        repeat (3) @(posedge clk);
        #1;
        check_reset;
        clear_observers;
        @(negedge clk);
        #1;
        resetn = 1'b1;
        wait (row_latches >= 34);

        if (failures == 0)
            $display("PASS tb_hub75e_scan: 64 ordered pixels, 32 rows, 67 clocks/row, LAT/blank and reset");
        else
            $display("FAIL tb_hub75e_scan: %0d errors", failures);
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL tb_hub75e_scan: timeout (address=%h frame=%b row_latches=%0d)",
                 ram_addr, frame_clk, row_latches);
        $finish;
    end
endmodule
