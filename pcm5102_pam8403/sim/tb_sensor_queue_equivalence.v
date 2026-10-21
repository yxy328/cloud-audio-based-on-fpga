`timescale 1ns/1ps
module tb_sensor_queue_equivalence;
reg clk=0;always #10 clk=~clk;
reg resetn=0,frame_ce=0,sensor_ready=1,gesture_valid=0,dir_evaluated=1,ir_note_valid=0;
reg [2:0] start_dir=1,end_dir=2,ir_note_index=0,control_timbre=0;
reg control_vibrato=0,control_bank=0,test32=0;
reg [129:0] adsr_config=0;
wire signed [15:0] audio_sample,reference_sample;
wire [31:0] voice_active,reference_active;
wire [5:0] voice_count,reference_count;
wire overrun,reference_overrun;
sensor_poly_audio dut(.tuning_ratio(16'd16384),.vibrato_inc(32'd527766),.vibrato_depth(10'd256),.vibrato_delay(16'd0),.vibrato_update(1'b0),.*);
sensor_poly_audio_reference reference(.clk(clk),.resetn(resetn),.frame_ce(frame_ce),.sensor_ready(sensor_ready),.gesture_valid(gesture_valid),.dir_evaluated(dir_evaluated),.start_dir(start_dir),.end_dir(end_dir),.ir_note_valid(ir_note_valid),.ir_note_index(ir_note_index),.control_timbre(control_timbre),.control_vibrato(control_vibrato),.control_bank(control_bank),.test32(test32),.adsr_config(adsr_config),.audio_sample(reference_sample),.voice_active(reference_active),.voice_count(reference_count),.overrun(reference_overrun));
integer n,checks=0,pops=0,pairs=0,wraps=0;
reg [3:0] pair_positions=0;
reg [31:0] random=32'h7be132a9;
always @(posedge clk)if(resetn)begin
 if(dut.pop)begin
  if(dut.next_event!==reference.next_event)$fatal(1,"Queue atomic metadata mismatch cycle=%0d",n);
  pops=pops+1;
 end
 if(dut.pushes==2)begin pairs=pairs+1;pair_positions[dut.wr]=1;end
 if(dut.config_wr==3 && dut.pushes!=0)wraps=wraps+1;
 #1;
 if({audio_sample,voice_active,voice_count,overrun,dut.queued,dut.wr,dut.rd,dut.test_pending}!=={reference_sample,reference_active,reference_count,reference_overrun,reference.queued,reference.wr,reference.rd,reference.test_pending})$fatal(1,"Queue cycle/output mismatch cycle=%0d",n);
 checks=checks+1;
end
initial begin
 repeat(5)@(negedge clk);
 for(n=0;n<250000;n=n+1)begin
  random=random^(random<<13);random=random^(random>>17);random=random^(random<<5);
  resetn=(n%55519)>3;frame_ce=(n%1024)==600;
  ir_note_valid=(n%211<129) || random[0];gesture_valid=(n%211<129) || random[1];
  sensor_ready=random[2];dir_evaluated=random[3];control_timbre=random[6:4];ir_note_index=random[9:7];
  case(random[11:10])
   0:begin start_dir=1;end_dir=2;end 1:begin start_dir=3;end_dir=4;end
   2:begin start_dir=2;end_dir=1;end 3:begin start_dir=4;end_dir=3;end
  endcase
  control_bank=random[12];control_vibrato=random[13];test32=n%8191==530;
  adsr_config={random[1:0],random,~random,random^32'hb29dfea7,random+32'd131};
  @(negedge clk);
 end
 if(pops<500 || pairs<16 || wraps<100 || pair_positions!=15)$fatal(1,"Insufficient queue stress coverage pops=%0d pairs=%0d wraps=%0d",pops,pairs,wraps);
 $display("PASS shared sensor config queue: %0d cycle/PCM comparisons, %0d pops, %0d dual pushes, %0d metadata pool wraps, full/backpressure/reset/test-command races",checks,pops,pairs,wraps);$finish;
end
endmodule
