`timescale 1ns/1ps
module tb_control12_dense;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,request=0;reg [2:0] operation=0;
    reg [15:0] arg0=0,arg1=0,arg2=0,arg3=0;
    wire done,valid,playing,gate,ms_tick,guide_reset,note_spawn,busy;
    wire [2:0] error;wire [7:0] current_note;wire [11:0] guide_keys,spawn_keys;
    wire [15:0] spawn_delay_ms,score_ratio;wire [12:0] current_mask;
    downloadable_song #(.CONTROL_KEYS(12),.CLK_HZ(1000000),.ENABLE_LOOKAHEAD(1),.LOOKAHEAD_MS(5)) dut(
        .clk(clk),.resetn(resetn),.request(request),.operation(operation),.arg0(arg0),.arg1(arg1),.arg2(arg2),.arg3(arg3),
        .score_min(16'd8192),.score_max(16'd32768),.score_ratio(score_ratio),.edit_allowed(1'b1),
        .note_map({8'd71,8'd70,8'd69,8'd68,8'd67,8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60}),
        .toggle_play(1'b0),.restart(1'b0),.done(done),.error(error),.valid(valid),.playing(playing),.gate(gate),
        .current_note(current_note),.guide_keys(guide_keys),.ms_tick(ms_tick),.guide_reset(guide_reset),
        .note_spawn(note_spawn),.spawn_keys(spawn_keys),.spawn_delay_ms(spawn_delay_ms),.note_ready(1'b1),.current_mask(current_mask),.busy(busy));
    function [11:0] keys;input integer event_number;begin
        keys=event_number%13==12 ? 0 : 12'b1<<(event_number%12);
    end endfunction
    task command;input [2:0] op;input [15:0] a,b,c,d;begin
        @(negedge clk);operation=op;arg0=a;arg1=b;arg2=c;arg3=d;request=1;
        @(negedge clk);request=0;wait(done);@(negedge clk);
        if(error!=0)$fatal(1,"dense command %0d error%0d",op,error);
    end endtask
    integer spawned=0,next_spawn=0,heard=0,k,expected_spawn=0;
    reg checking=0;integer event_number;
    always @(negedge clk)if(checking && note_spawn)begin
        while(next_spawn<128 && keys(next_spawn)==0)next_spawn=next_spawn+1;
        if(next_spawn>=128 || spawn_keys!==keys(next_spawn))$fatal(1,"dense lookahead key at%0d got%h",next_spawn,spawn_keys);
        spawned=spawned+1;next_spawn=next_spawn+1;
    end
    always @(posedge clk)if(checking && ms_tick && dut.state==5)begin
        event_number=dut.elapsed_ms+1-5;
        #1;
        if(event_number>=0 && event_number<128)begin
            if(guide_keys!==keys(event_number))$fatal(1,"dense event%0d got%h expected%h",event_number,guide_keys,keys(event_number));
            if(keys(event_number)!=0 && (!gate || score_ratio!==(event_number[0] ? 16'd24576 : 16'd16384)))$fatal(1,"dense bend/gate event%0d",event_number);
            heard=heard+1;
        end
    end
    initial begin
        repeat(4)@(negedge clk);resetn=1;command(1,128,0,0,0);
        for(k=0;k<128;k=k+1)begin
            command(6,k,{1'b0,keys(k)},1,keys(k)==0 ? 0 : k[0] ? 24576 : 16384);
            if(keys(k)!=0)expected_spawn=expected_spawn+1;
        end
        command(3,0,0,0,0);checking=1;command(4,0,0,0,0);
        wait(!playing);@(negedge clk);
        if(heard!=128 || spawned!=expected_spawn || guide_keys!=0)$fatal(1,"dense dropped events: heard%0d spawned%0d/%0d",heard,spawned,expected_spawn);
        $display("PASS control12 dense score: 128 x1ms across all12 keys, rests, per-event bend targets, %0d lookahead emissions, no drops",spawned);$finish;
    end
    initial begin #10000000;$fatal(1,"dense timeout");end
endmodule
