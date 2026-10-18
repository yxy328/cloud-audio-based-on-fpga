`timescale 1ns/1ps
// Independent wire-level model: snapshot on the first falling edge after
// serial timeout, D0 first, output propagation delay, idle/DV and disconnect.
module ttp229_model #(
    parameter integer TIMEOUT_NS=2000000,
    parameter integer PROP_NS=40
)(input wire rst_n, scl, connected, dv, stuck_low,
  input wire [15:0] keys, output wire sdo);
    reg data=1;
    reg [15:0] latched=0;
    integer bit_count=0, frames=0;
    time last_fall=0;
    assign sdo = !connected ? 1'bz : (dv || stuck_low) ? 1'b0 : data;
    always @(negedge scl or negedge rst_n) begin
        if(!rst_n) begin data=1; bit_count=0; frames=0; last_fall=0; end
        else begin
            if($time-last_fall>TIMEOUT_NS) bit_count=0;
            if(bit_count==0) latched=keys;
            if(bit_count>=16) $fatal(1,"More than 16 clocks without serial timeout");
            last_fall=$time;
            data <= #PROP_NS ~latched[bit_count];
            bit_count=bit_count+1;
        end
    end
    always @(posedge scl) if(rst_n && bit_count==16) begin
        data <= #TIMEOUT_NS 1;
        frames=frames+1;
    end
endmodule
