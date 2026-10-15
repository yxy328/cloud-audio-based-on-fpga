`timescale 1ns/1ps

// Use the manufacturer's gw5a/prim_sim.v, not an inferred memory substitute.
// Run from the project directory, or pass +IMAGE_DIR=<absolute src directory>.
module tb_display_rom;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg image_sel = 1'b0;
    reg [10:0] ad = 11'd0;
    wire [31:0] dout;
    reg [31:0] expected_t [0:2047];
    reg [31:0] expected_s [0:2047];
    reg [31:0] previous_data;
    reg [31:0] expected_data;
    reg [2047:0] image_dir;
    integer image;
    integer address;

    // Gowin simulation primitives reference this exact global instance name.
    GSR GSR (.GSRI(1'b1));

    display_rom dut (
        .clk(clk), .reset(reset), .ad(ad), .image_sel(image_sel), .dout(dout)
    );

    always #5 clk = ~clk;

    task load_image;
        input [2047:0] filename;
        input integer select_s;
        integer fd;
        integer chars;
        integer matched;
        integer count;
        reg [1023:0] line;
        reg [31:0] word_value;
        begin
            fd = $fopen(filename, "r");
            if (fd == 0)
                $fatal(1, "Cannot open image: %0s", filename);
            count = 0;
            while (!$feof(fd)) begin
                chars = $fgets(line, fd);
                matched = $sscanf(line, "%h", word_value);
                // Gowin's three # metadata lines intentionally do not parse.
                if ((chars != 0) && (matched == 1)) begin
                    if (count >= 2048)
                        $fatal(1, "Too many image words: %0s", filename);
                    if (select_s)
                        expected_s[count] = word_value;
                    else
                        expected_t[count] = word_value;
                    count = count + 1;
                end
            end
            $fclose(fd);
            if (count != 2048)
                $fatal(1, "Image %0s has %0d words, expected 2048", filename, count);
        end
    endtask

    initial begin
        if (!$value$plusargs("IMAGE_DIR=%s", image_dir))
            image_dir = "src";
        load_image({image_dir, "/logoT.hex"}, 0);
        load_image({image_dir, "/logoS.hex"}, 1);
        repeat (2) @(posedge clk);
        #1;
        if (dout !== 32'd0)
            $fatal(1, "Synchronous reset did not clear ROM output");
        @(negedge clk);
        reset = 1'b0;

        // Establish a known previous read before checking edge-to-edge holds.
        @(posedge clk);
        #1;
        if (dout !== expected_t[0])
            $fatal(1, "First read after reset has the wrong latency/data");

        for (image = 0; image < 2; image = image + 1) begin
            for (address = 0; address < 2048; address = address + 1) begin
                @(negedge clk);
                image_sel = image;
                // Allow the combinational image mux to settle, then change AD.
                #1;
                previous_data = dout;
                ad = address;
                #1;
                if (dout !== previous_data)
                    $fatal(1, "Asynchronous read detected: image=%0d ad=%0d", image, address);
                @(posedge clk);
                #1;
                expected_data = image ? expected_s[address] : expected_t[address];
                if (dout !== expected_data)
                    $fatal(1, "ROM mismatch: image=%0d ad=%0d got=%08h expected=%08h",
                           image, address, dout, expected_data);
            end
        end

        // Both images must be available at the current address without a read.
        @(negedge clk);
        image_sel = 1'b0;
        #1;
        if (dout !== expected_t[2047])
            $fatal(1, "Switching to logoT added an unexpected clock cycle");
        image_sel = 1'b1;
        #1;
        if (dout !== expected_s[2047])
            $fatal(1, "Switching to logoS added an unexpected clock cycle");

        // RESET_MODE=SYNC: assertion alone preserves data until the next edge.
        previous_data = dout;
        reset = 1'b1;
        #1;
        if (dout !== previous_data)
            $fatal(1, "Reset behaved asynchronously");
        @(posedge clk);
        #1;
        if (dout !== 32'd0)
            $fatal(1, "logoS output did not reset");
        image_sel = 1'b0;
        #1;
        if (dout !== 32'd0)
            $fatal(1, "logoT output did not reset");
        @(negedge clk);
        reset = 1'b0;
        ad = 11'd37;
        @(posedge clk);
        #1;
        if (dout !== expected_t[37])
            $fatal(1, "Read failed after synchronous reset");
        image_sel = 1'b1;
        #1;
        if (dout !== expected_s[37])
            $fatal(1, "logoS read failed after synchronous reset");
        $display("PASS: 4096 ROM words, synchronous one-edge reads, image mux and reset");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "ROM test timeout");
    end
endmodule
