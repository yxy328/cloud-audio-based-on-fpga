`timescale 1ns/1ps
module tb_dds_voice;
    reg clk = 0;
    always #10 clk = ~clk;
    reg resetn = 0;
    reg sample_ce = 0;
    reg [31:0] phase_inc = 0;
    wire signed [15:0] sample;
    dds_voice dut (.clk(clk), .resetn(resetn), .sample_ce(sample_ce),
                   .phase_inc(phase_inc), .sample(sample));
    reg [9:0] rom_address = 0;
    wire signed [15:0] rom_sample;
    sine_rom rom (.address(rom_address), .sample(rom_sample));
    reg [31:0] reference_phase = 0;
    integer i, j, expected, error, checks = 0;
    real value;
    function integer sine_reference;
        input integer address;
        real v;
        begin
            v = 32767.0 * $sin(6.283185307179586 * address / 1024.0);
            sine_reference = (v >= 0) ? $rtoi(v + 0.5) : $rtoi(v - 0.5);
        end
    endfunction
    task step;
        input [31:0] increment;
        input advance;
        begin
            @(negedge clk);
            phase_inc = increment;
            sample_ce = advance;
            #1;
            expected = sine_reference(reference_phase[31:22]);
            error = $signed(sample) - expected;
            if (error < -1 || error > 1)
                $fatal(1, "Changing pitch changed the current phase/sample");
            @(posedge clk);
            if (advance) reference_phase = reference_phase + increment;
            #1;
            expected = sine_reference(reference_phase[31:22]);
            error = $signed(sample) - expected;
            if (error < -1 || error > 1)
                $fatal(1, "DDS differs from mathematical sine: phase=%h expected=%0d actual=%0d", reference_phase, expected, $signed(sample));
            checks = checks + 1;
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        for (i=0; i<1024; i=i+1) begin
            rom_address = i;
            #1;
            error = $signed(rom_sample) - sine_reference(i);
            if (error < -1 || error > 1) $fatal(1, "Sine ROM address %0d is incorrect", i);
        end
        @(negedge clk) resetn = 1;
        for (i=0; i<1800; i=i+1) step(32'd38702809, 1);
        for (i=0; i<1800; i=i+1) step(32'd46025656, 1);
        for (i=0; i<1800; i=i+1) step(32'd57988693, 1);
        for (i=0; i<1800; i=i+1) step(32'd77405619, 1);
        for (i=0; i<1000; i=i+1) step($random, (i % 3 != 0));
        step(32'd0, 1);
        step(32'hffffffff, 1);
        step(32'h80000000, 0);
        @(negedge clk) begin resetn=0; sample_ce=0; end
        @(posedge clk); #1;
        if (sample !== 16'sd0) $fatal(1, "Reset did not restore zero phase");
        $display("PASS [DDS]: 1024 ROM addresses, %0d runtime phase/enable checks, continuous phase on pitch changes", checks);
        $finish;
    end
endmodule
