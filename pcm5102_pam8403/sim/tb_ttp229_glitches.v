`timescale 1ns/1ps
// Wire-level disturbances at production timing. Injection is timed from
// physical SCL edges, not the receiver's internal sampling registers.
module tb_ttp229_glitches;
    reg clk=0,rst_n=0,flip=0;
    reg [15:0] keys=0;
    integer mode=0,target_bit=0,wire_bit=0;
    wire scl,sensor_sdo,valid,scan_valid,scan_error;
    wire sdo=sensor_sdo ^ flip;
    wire [15:0] down,raw;
    wire [3:0] index;
    integer events=0,bad=0,before_events,before_bad,k,m;
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
        if(rst_n && (wire_bit+15)%16==target_bit) begin
            case(mode)
                // Both old endpoint samples see the same WRONG value.
                1:begin #9600;flip=1;#600;flip=0;#9400;flip=1;#600;flip=0;end
                // Both endpoints agree, but there was a mid-bit disturbance.
                2:begin #14000;flip=1;#500;flip=0;end
                // A late transition spans both old endpoint samples.
                3:begin #8000;flip=1;#12200;flip=0;end
            endcase
        end
    end
    task scans(input integer n);
        integer f;
        begin
            for(f=0;f<n;f=f+1) begin
                @(posedge scan_valid);repeat(40) @(negedge clk);
            end
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;scans(3);
        keys=16'h0004;scans(3);
        if(events!=1 || down!=4) $fatal(1,"Initial clean key3");
        for(m=1;m<=3;m=m+1) begin
            // Include first/last bits and the genuinely held key (bad release).
            for(k=0;k<4;k=k+1) begin
                case(k) 0:target_bit=0;1:target_bit=2;2:target_bit=7;3:target_bit=15;endcase
                before_events=events;before_bad=bad;mode=m;scans(4);mode=0;
                if(events!=before_events || down!=4 || bad-before_bad!=((m==3) ? 4 : 0) ||
                   (m!=3 && raw!=4))
                    $fatal(1,"Glitch mode=%0d bit=%0d: extra notes=%0d bad=%0d down=%h raw=%h",
                        m,target_bit,events-before_events,bad-before_bad,down,raw);
                scans(2);
                if(events!=before_events || down!=4) $fatal(1,"Recovery retriggered held key");
            end
        end
        keys=0;scans(3);before_events=events;
        keys=16'hFFFF;scans(3);
        if(events!=before_events+16 || down!=16'hFFFF) $fatal(1,"Full chord lost after glitches");
        keys=0;scans(3);keys=16'h8000;scans(3);
        if(events!=before_events+17 || down!=16'h8000) $fatal(1,"Key16/rearm lost");
        $display("PASS TTP229 window voting: 32 short-disturbed frames corrected, 16 long/ambiguous frames rejected, no false note/release, recovery and 16-key chord");
        $finish;
    end
    initial begin #350000000;$fatal(1,"Glitch test timeout");end
endmodule
