`timescale 1ns/1ps
module tb_score256;
    reg clk=0;always #5 clk=~clk;
    reg resetn=0,request=0;
    reg [2:0] op=0;
    reg [15:0] a=0,b=0,c=0,d=0;
    wire done,valid,playing,start,spawn,body;
    wire [2:0] error;
    wire [12:0] mask;
    wire [15:0] ratio,duration;
    wire [1:0] kind,spawn_kind;
    wire [11:0] guide,spawn_keys;
    downloadable_song #(.CLK_HZ(100000),.CONTROL_KEYS(12),.TRUSTED_MAP(1),
        .ENABLE_LOOKAHEAD(1),.LOOKAHEAD_MS(20)) dut(
        .clk(clk),.resetn(resetn),.request(request),.operation(op),
        .arg0(a),.arg1(b),.arg2(c),.arg3(d),.score_min(16'd8192),.score_max(16'd32768),
        .edit_allowed(1'b1),.note_map({8'd71,8'd70,8'd69,8'd68,8'd67,8'd66,8'd65,8'd64,8'd63,8'd62,8'd61,8'd60}),
        .toggle_play(1'b0),.restart(1'b0),.note_ready(1'b1),
        .done(done),.error(error),.valid(valid),.playing(playing),.current_mask(mask),
        .score_ratio(ratio),.guide_keys(guide),.event_start(start),.event_duration(duration),
        .event_type(kind),.note_spawn(spawn),.spawn_body(body),.spawn_type(spawn_kind),.spawn_keys(spawn_keys));
    integer waited,i,sounding=0,heads=0,expected_ms=20;
    reg verify=0,bank;
    function [12:0] pitches;
        input integer index;
        begin pitches=index%11==0 ? 13'd0 : 13'd1<<(index%12);end
    endfunction
    function [15:0] milliseconds;
        input integer index;
        begin milliseconds=5+index%3;end
    endfunction
    task command;
        input [2:0] operation;input [15:0] x,y,z,t;input [2:0] expected;
        begin
            @(negedge clk);op=operation;a=x;b=y;c=z;d=t;request=1;
            @(negedge clk);request=0;waited=0;
            while(!done && waited<3000)begin @(negedge clk);waited=waited+1;end
            if(!done || error!==expected)$fatal(1,"op%0d index%0d expected%0d got%0d",operation,x,expected,error);
            @(negedge clk);
        end
    endtask
    task record;
        input integer index;
        reg [15:0] packed_mask;
        begin
            packed_mask=pitches(index)==0 ? 0 : (((index%4)+1)<<13)|pitches(index);
            command(6,index,packed_mask,milliseconds(index),8192+index,0);
        end
    endtask
    always @(posedge clk)begin
        #1;
        if(verify && start)begin
            if(sounding>=256 || mask!==pitches(sounding) || ratio!==8192+sounding ||
               duration!==milliseconds(sounding) || guide!==pitches(sounding) ||
               (mask!=0 && kind!==sounding%4) || dut.elapsed_ms!==expected_ms)
                $fatal(1,"playback mismatch at event %0d, elapsed%0d expected%0d",sounding,dut.elapsed_ms,expected_ms);
            expected_ms=expected_ms+milliseconds(sounding);sounding=sounding+1;
        end
        if(verify && spawn && !body)heads=heads+1;
    end
    initial begin
        repeat(3)@(negedge clk);resetn=1;
        command(1,0,0,0,0,2);command(1,257,0,0,0,2);
        command(1,1,0,0,0,0);command(2,0,60,2,0,0);command(3,0,0,0,0,0);bank=dut.active_bank;
        command(1,256,0,0,0,0);
        command(6,256,1,5,8192,2);command(6,16'hff00,1,5,8192,2);
        // Reverse order, duplicate overwrite, and a hole above the old boundary.
        for(i=255;i>=0;i=i-1)if(i!=128)record(i);
        record(127);command(3,0,0,0,0,4);
        if(!valid || dut.active_bank!==bank)$fatal(1,"incomplete download replaced active bank");
        command(4,0,0,0,0,0);wait(start);#2;
        if(mask!==1 || duration!==2)$fatal(1,"old active song was damaged");
        command(5,0,0,0,0,0);
        record(128);command(3,0,0,0,0,0);
        if(dut.active_count!==9'd256 || dut.active_bank===bank)$fatal(1,"256 count or bank swap");
        verify=1;command(4,0,0,0,0,0);wait(!playing);repeat(5)@(negedge clk);verify=0;
        if(sounding!=256 || heads!=232)$fatal(1,"lost events: sounding%0d heads%0d",sounding,heads);
        bank=dut.active_bank;
        command(1,256,0,0,0,0);command(3,0,0,0,0,4);
        if(!valid || dut.active_bank!==bank)$fatal(1,"stale staging data accepted");
        // STOP can cancel a clear without damaging the valid active song.
        @(negedge clk);op=1;a=256;request=1;@(negedge clk);request=0;
        repeat(20)@(negedge clk);command(5,0,0,0,0,0);
        if(dut.staging || !valid || dut.active_bank!==bank)$fatal(1,"clear cancellation damaged state");
        $display("PASS score256: reverse/duplicate writes, hole128, addresses127/128/255, all four types and bends, exact playback, 232 visual heads, stale-bank rejection, clear cancellation");
        $finish;
    end
    initial begin #20000000;$fatal(1,"score256 timeout");end
endmodule
