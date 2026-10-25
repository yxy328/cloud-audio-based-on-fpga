`timescale 1ns/1ps
module tb_key_live_stream;
    reg clk=0;
    always #5 clk=~clk;
    reg resetn=0, enable=0, tx_ready=1;
    reg [15:0] scan_keys=0;
    wire tx_valid, tx_last;
    wire [7:0] tx_data;
    key_live_stream dut(.*);
    reg [63:0] lines[0:63];
    reg [63:0] line=0;
    integer line_count=0;
    reg stalled=0;
    reg [7:0] stalled_data;
    reg stalled_last;
    always @(posedge clk) begin
        if(resetn) begin
            if(stalled && (tx_data!==stalled_data || tx_last!==stalled_last || !tx_valid))
                $fatal(1,"live stream did not hold a stalled byte");
            stalled=tx_valid && !tx_ready;
            stalled_data=tx_data; stalled_last=tx_last;
            if(tx_valid && tx_ready) begin
                line={line[55:0],tx_data};
                if(tx_last!==(tx_data==10)) $fatal(1,"tx_last must identify LF");
                if(tx_last) begin
                    lines[line_count]=line;
                    line_count=line_count+1; line=0;
                end
            end
        end else begin stalled=0; line=0; end
    end
    task expect;
        input integer index;
        input [63:0] text;
        begin
            if(line_count<=index) $fatal(1,"missing line %0d",index);
            if(lines[index]!=text) $fatal(1,"line %0d = %h, expected %h",index,lines[index],text);
        end
    endtask
    task wait_lines;
        input integer target;
        integer deadline;
        begin
            deadline=0;
            while(line_count<target && deadline<4000) begin @(negedge clk); deadline=deadline+1; end
            if(line_count<target) $fatal(1,"timeout waiting for %0d lines",target);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);
        resetn=1;
        repeat(2) @(negedge clk);
        // Keys already held when the link enables are seeded as press events.
        @(negedge clk); scan_keys=16'h0001; enable=1;
        wait_lines(1); expect(0, {"K,01,1",8'd13,8'd10});
        // A stalled UART must not corrupt or drop the byte in flight.
        @(negedge clk); scan_keys=0; tx_ready=0;
        repeat(25) @(negedge clk);
        tx_ready=1;
        wait_lines(2); expect(1, {"K,01,0",8'd13,8'd10});
        // Simultaneous changes queue in ascending key order.
        @(negedge clk); scan_keys=16'h000C;
        wait_lines(4); expect(2, {"K,03,1",8'd13,8'd10}); expect(3, {"K,04,1",8'd13,8'd10});
        // Two-digit key numbers keep the fixed width.
        @(negedge clk); scan_keys=16'h800C;
        wait_lines(5); expect(4, {"K,16,1",8'd13,8'd10});
        // Disabling clears the queue; re-enabling reseeds the held keys.
        @(negedge clk); enable=0;
        repeat(4) @(negedge clk);
        @(negedge clk); enable=1;
        wait_lines(8); expect(5, {"K,03,1",8'd13,8'd10}); expect(6, {"K,04,1",8'd13,8'd10}); expect(7, {"K,16,1",8'd13,8'd10});
        // A frame already in flight completes after enable drops; the rest is dropped.
        @(negedge clk); scan_keys=16'h8000;
        repeat(3) @(negedge clk);
        enable=0;
        wait_lines(9); expect(8, {"K,03,0",8'd13,8'd10});
        repeat(300) @(negedge clk);
        if(line_count!=9) $fatal(1,"disable must drop queued lines, got %0d",line_count);
        $display("PASS key_live_stream: %0d lines, framing and queueing verified",line_count);
        $finish;
    end
endmodule
