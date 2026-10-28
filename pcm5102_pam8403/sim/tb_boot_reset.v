`timescale 1ns/1ps
module tb_boot_reset;
reg clk=0; always #10 clk=~clk;
top dut(.clk(clk));
integer edges=0;
initial begin
 #1;
 if(dut.resetn!==0)$fatal(1,"boot initial state");
 repeat(256)begin
  @(posedge clk);edges=edges+1;#1;
  if(dut.resetn!==(edges>=63))$fatal(1,"boot reset phase at edge %0d",edges);
 end
 $display("PASS boot reset: actual top reset releases at edge63 and remains released, 256 checked clocks");
 $finish;
end
endmodule
