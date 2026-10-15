`timescale 1ns/1ps
module tb_performance_logger;
    reg clk=0;
    always #5 clk=~clk;
    reg resetn=0, start=0, stop=0, tx_ready=1;
    reg [55:0] note_map={8'd72,8'd69,8'd67,8'd65,8'd64,8'd62,8'd60};
    reg [6:0] touch_keys=0;
    reg pressure_mode=0;
    reg [15:0] volume_gain=39321, pitch_ratio=65535;
    wire recording, tx_valid, tx_last;
    wire [7:0] tx_data;
    wire [31:0] dropped;
    performance_logger #(.CLK_HZ(100000),.FIFO_DEPTH(64)) dut(.*);
    reg [1023:0] lines[0:255];
    reg [1023:0] line=0;
    integer line_count=0, i, deadline;
    reg stalled=0;
    reg [7:0] stalled_data;
    reg stalled_last;
    always @(posedge clk) begin
        if(resetn) begin
            if(stalled && (tx_data!==stalled_data || tx_last!==stalled_last || !tx_valid))
                $fatal(1,"logger did not hold a stalled byte");
            stalled=tx_valid && !tx_ready;
            stalled_data=tx_data; stalled_last=tx_last;
            if(tx_valid && tx_ready) begin
                line={line[1015:0],tx_data};
                if(tx_last!==(tx_data==10)) $fatal(1,"tx_last must identify LF");
                if(tx_last) begin
                    lines[line_count]=line;
                    line_count=line_count+1; line=0;
                end
            end
        end else begin stalled=0; line=0; end
    end
    task at_ms;
        input integer target;
        begin while(dut.elapsed_ms<target) @(negedge clk); end
    endtask
    task begin_recording;
        begin
            @(negedge clk); start=1;
            @(negedge clk); start=0;
            if(!recording) $fatal(1,"REC_START was not accepted");
        end
    endtask
    task end_recording;
        begin
            stop=1;
            @(negedge clk); stop=0;
            deadline=0;
            while(recording && deadline<100000) begin @(negedge clk); deadline=deadline+1; end
            if(recording) $fatal(1,"REC_STOP did not drain");
        end
    endtask
    task expect_line;
        input integer index;
        input [1023:0] expected;
        begin
            if(lines[index]!==expected)
                $fatal(1,"line %0d: got '%0s', expected '%0s'",index,lines[index],expected);
        end
    endtask
    initial begin #5000000; $fatal(1,"logger timeout"); end
    initial begin
        repeat(3) @(negedge clk); resetn=1;
        begin_recording;
        at_ms(120); touch_keys=1;
        at_ms(650); touch_keys=0;
        at_ms(660); touch_keys=3;
        at_ms(665); touch_keys=7;
        at_ms(670); touch_keys=0;
        at_ms(673); pressure_mode=1; volume_gain=12345; pitch_ratio=60000;
        at_ms(710); end_recording;
        if(dropped!=0 || line_count!=10) $fatal(1,"unexpected event count %0d/drop %0d",line_count,dropped);
        expect_line(0,{"MAP,60,62,64,65,67,69,72",8'd13,8'd10});
        expect_line(1,{"EVT,0,00,0,39321,65535",8'd13,8'd10});
        expect_line(2,{"EVT,120,01,0,39321,65535",8'd13,8'd10});
        expect_line(3,{"EVT,650,00,0,39321,65535",8'd13,8'd10});
        expect_line(4,{"EVT,660,03,0,39321,65535",8'd13,8'd10});
        expect_line(5,{"EVT,665,07,0,39321,65535",8'd13,8'd10});
        expect_line(6,{"EVT,670,00,0,39321,65535",8'd13,8'd10});
        expect_line(7,{"EVT,680,00,1,12345,60000",8'd13,8'd10});
        expect_line(8,{"EVT,710,00,1,12345,60000",8'd13,8'd10});
        expect_line(9,{"REC_END,0",8'd13,8'd10});

        // Stall UART on MAP: all 64 FIFO slots remain available, including
        // initial state. Overflow is explicit and STOP has its own final slot.
        line_count=0; touch_keys=0; pressure_mode=0; volume_gain=0; pitch_ratio=65535;
        tx_ready=0;
        begin_recording;
        // REC_START while draining/capturing must not reset the active take.
        repeat(5) @(negedge clk);
        start=1; @(negedge clk); start=0;
        for(i=0;i<70;i=i+1) begin
            @(negedge clk); touch_keys=i+1;
        end
        @(negedge clk); touch_keys=7'h7f; stop=1;
        @(negedge clk); stop=0;
        if(dropped!=7) $fatal(1,"full FIFO expected 7 dropped changes, got %0d",dropped);
        tx_ready=1;
        deadline=0;
        while(recording && deadline<100000) begin @(negedge clk); deadline=deadline+1; end
        if(recording || line_count!=68) $fatal(1,"FIFO drain failed: %0d lines",line_count);
        expect_line(0,{"MAP,60,62,64,65,67,69,72",8'd13,8'd10});
        expect_line(1,{"ERR,REC_OVERFLOW,7",8'd13,8'd10});
        expect_line(2,{"EVT,0,00,0,0,65535",8'd13,8'd10});
        expect_line(65,{"EVT,0,3F,0,0,65535",8'd13,8'd10});
        expect_line(66,{"EVT,0,7F,0,0,65535",8'd13,8'd10});
        expect_line(67,{"REC_END,7",8'd13,8'd10});
        $display("PASS tb_performance_logger: MAP, press/hold/release/chords, pressure, FIFO64, overflow, STOP");
        $finish;
    end
endmodule
