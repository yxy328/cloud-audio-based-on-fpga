`timescale 1ns/1ps
module tb_score_bend_words;
reg clk=0,resetn=0,request=0;
always #10 clk=~clk;
reg [2:0] op=0;reg [15:0] a=0,b=0,c=0,d=0,lo=8192,hi=32768;
wire done,valid,playing,gate;wire [2:0] error;
wire [15:0] ratio;wire [12:0] mask;
downloadable_song #(.CLK_HZ(1000)) dut(.clk(clk),.resetn(resetn),.request(request),.operation(op),
 .arg0(a),.arg1(b),.arg2(c),.arg3(d),.score_min(lo),.score_max(hi),.edit_allowed(1'b1),
 .note_map({8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60}),.toggle_play(1'b0),.restart(1'b0),.note_ready(1'b1),
 .done(done),.error(error),.valid(valid),.playing(playing),.gate(gate),.current_mask(mask),.score_ratio(ratio));
integer n,bank_before,checks=0;
task command;
 input [2:0] operation;input [15:0] x,y,z,t;input [2:0] expected;
 begin @(negedge clk);op=operation;a=x;b=y;c=z;d=t;request=1;@(negedge clk);request=0;
     while(!done)@(negedge clk);
     if(error!==expected)$fatal(1,"Command op=%d error=%d expected=%d",op,error,expected);
     checks=checks+1;@(negedge clk);
 end
endtask
initial begin
 repeat(3)@(negedge clk);resetn=1;
 command(1,2,0,0,0,0);command(6,0,1,20,20000,0);command(6,1,2,20,12000,0);command(3,0,0,0,0,0);
 if(!valid)$fatal(1,"Not committed");bank_before=dut.active_bank;
 command(4,0,0,0,0,0);wait(playing && gate && mask==1);#1;if(ratio!==20000)$fatal(1,"First target");
 wait(playing && gate && mask==2);#1;if(ratio!==12000)$fatal(1,"Next target");wait(!playing);
 lo=15000;hi=25000;command(4,0,0,0,0,2);if(playing)$fatal(1,"Out-of-range PLAY started");lo=8192;hi=32768;
 command(1,1,0,0,0,0);command(6,0,1,20,20000,0);hi=19000;command(3,0,0,0,0,2);
 if(dut.active_bank!==bank_before)$fatal(1,"Rejected END replaced active score");hi=32768;
 command(1,128,0,0,0,0);
 for(n=0;n<128;n=n+1)command(6,n,1,60000,n[0]?32768:8192,0);
 command(3,0,0,0,0,0);
 if(dut.active_count!==128)$fatal(1,"128-event geometry reduced");
 for(n=0;n<128;n=n+1)begin
     if(dut.score[{dut.active_bank,n[7:0]}][15:0]!==60000 || dut.score[{dut.active_bank,n[7:0]}][44:29]!==(n[0]?16'd32768:16'd8192))$fatal(1,"Truncated event %d",n);
 end
 $display("PASS D target words: both event targets, active bank preserved on failed END, current-range PLAY validation, 128x60000ms full-width data (%0d commands)",checks);$finish;
end
initial begin #10000000;$fatal(1,"Score words timeout");end
endmodule
