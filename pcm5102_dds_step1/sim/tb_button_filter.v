`timescale 1ns/1ps
module tb_button_filter;
    reg clk=0;
    always #10 clk=~clk;
    reg resetn=0, button=0;
    wire level, pressed;
    button_filter #(.CONFIRM_CYCLES(4)) dut (
        .clk(clk), .resetn(resetn), .button(button), .level(level), .pressed(pressed));
    integer presses=0;
    always @(posedge clk) if (resetn && pressed) presses=presses+1;
    initial begin
        repeat(3) @(negedge clk);
        resetn=1;
        @(negedge clk) button=1;
        repeat(2) @(negedge clk);
        button=0;
        repeat(10) @(negedge clk);
        if (level || presses != 0) $fatal(1,"Short bounce caused an event");
        button=1;
        repeat(12) @(negedge clk);
        if (!level || presses != 1) $fatal(1,"Confirmed press missing");
        repeat(40) @(negedge clk);
        if (presses != 1) $fatal(1,"Held key repeated");
        button=0;
        repeat(2) @(negedge clk);
        button=1;
        repeat(10) @(negedge clk);
        if (!level || presses != 1) $fatal(1,"Short release bounce changed state");
        button=0;
        repeat(12) @(negedge clk);
        if (level) $fatal(1,"Release not confirmed");
        button=1;
        repeat(12) @(negedge clk);
        if (!level || presses != 2) $fatal(1,"Second physical press missing");
        $display("PASS [buttons]: short bounce ignored, one event per hold, release/repress accepted");
        $finish;
    end
endmodule
