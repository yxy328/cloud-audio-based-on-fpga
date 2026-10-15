`timescale 1ns/1ps
// Independent serial model based on datasheet figure 5-1. Locate the start
// bit on the wire, then output null/B9..B0 on falling edges with 200ns delay.
module mcp3008_model #(
    parameter [2:0] EXPECT_CHANNEL = 3'd0
) (
    input wire resetn,
    input wire cs_n,
    input wire sclk,
    input wire mosi,
    input wire [9:0] analog_code,
    output reg miso
);
    integer clocks=0, start_clock=0, relative_clock;
    integer transactions=0;
    reg [23:0] command=0;
    reg [9:0] conversion=0;
    reg [23:0] expected_command;
    initial miso=1'bz;
    always @(negedge cs_n) begin
        clocks=0;start_clock=0;command=0;conversion=analog_code;
        miso=1'bz;
        if(sclk!==0) $fatal(1,"ADC CS asserted with SCLK high");
    end
    always @(posedge sclk) begin
        if(cs_n!==0) $fatal(1,"ADC clock outside chip select");
        clocks=clocks+1;
        command={command[22:0],mosi};
        if(start_clock==0 && mosi===1'b1) start_clock=clocks;
    end
    always @(negedge sclk) begin
        if(cs_n===0 && start_clock!=0) begin
            relative_clock=clocks-start_clock;
            if(relative_clock==5) begin #200;miso=0;end
            else if(relative_clock>=6 && relative_clock<=15) begin
                #200;miso=conversion[15-relative_clock];
            end
        end
    end
    always @(posedge cs_n) begin
        if(clocks!=0 && resetn) begin
            expected_command={7'd0,1'b1,1'b1,EXPECT_CHANNEL,12'd0};
            if(clocks!=24 || start_clock!=8 || command!==expected_command)
                $fatal(1,"ADC command/clock count invalid: clocks=%0d start=%0d command=%h",clocks,start_clock,command);
            transactions=transactions+1;
        end
        miso=1'bz;
    end
endmodule
