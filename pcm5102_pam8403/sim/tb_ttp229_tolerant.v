`timescale 1ns/1ps
// A short disturbance on EVERY frame must not starve a real press/release.
// fix25 fails this test; its whole-frame rejection made touch less usable.
module tb_ttp229_tolerant;
    reg clk=0,rst_n=0,flip=0,noise=0;
    reg [15:0] keys=0;
    wire scl,sensor_sdo,valid,scan_valid,scan_error;
    wire sdo=sensor_sdo ^ flip;
    wire [15:0] down,raw;
    wire [3:0] index;
    integer wire_bit=0,events=0,bad=0;
    always #10 clk=~clk;
    ttp229_keys #(.STARTUP_CYCLES(8)) dut(
        .clk(clk),.rst_n(rst_n),.sdo(sdo),.scl(scl),.keys_down(down),
        .raw_keys(raw),.scan_valid(scan_valid),.scan_error(scan_error),
        .note_valid(valid),.note_index(index),.note_ready(1'b1));
    ttp229_model sensor(.rst_n(rst_n),.scl(scl),.connected(1'b1),
        .dv(1'b0),.stuck_low(1'b0),.keys(keys),.sdo(sensor_sdo));
    always @(posedge clk) if(rst_n) begin
        if(valid) events=events+1;
        if(scan_valid && scan_error) bad=bad+1;
    end
    always @(negedge scl) if(rst_n) wire_bit=(wire_bit+1)%16;
    always @(negedge scl) begin
        #1;
        if(rst_n && noise && (wire_bit==1 || wire_bit==7)) begin
            #9600;flip=1;#600;flip=0;#9400;flip=1;#600;flip=0;
        end
    end
    task settle;begin #6500000;end endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;settle;noise=1;settle;
        keys=1;settle;
        if(down!=1 || events!=1 || bad) $fatal(1,"Brief repeated noise starved key1 press: down=%h bad=%0d",down,bad);
        keys=0;settle;if(down || events!=1 || bad) $fatal(1,"Repeated noise starved key1 release");
        keys=16'h0041;settle;
        if(down!=16'h0041 || events!=3 || bad) $fatal(1,"Repeated noise starved real 1+7 chord");
        keys=16'h0040;settle;keys=16'h0041;settle;
        if(events!=4 || down!=16'h0041) $fatal(1,"Noisy independent rearm");
        keys=0;settle;keys=16'hFFFF;settle;
        if(down!=16'hFFFF || events!=20 || bad) $fatal(1,"Noisy 16-key chord");
        $display("PASS short-noise tolerance: continuous paired endpoint pulses, responsive press/release/rearm, genuine 1+7 and 16-key chords, no bad-frame starvation");
        $finish;
    end
    initial begin #100000000;$fatal(1,"Tolerant touch timeout");end
endmodule
