`timescale 1ns/1ps
module tb_uart_8n1;
    // Production bit period by default; byte-only test has no audio overhead.
    localparam BIT_TICKS=5208;
    reg clk=0; always #10 clk=~clk;
    reg resetn=0,rx=1,consume=1;
    wire tx,valid,tx_ready,fault;
    wire [7:0] data;
    reg [7:0] decoded,received[0:511];
    integer count=0,faults=0,b,n,old_count;
    uart_8n1 #(.CLK_HZ(50000000),.BAUD(9600)) dut(
        .clk(clk),.resetn(resetn),.rx(rx),.tx(tx),
        .rx_data(data),.rx_valid(valid),.rx_ready(consume && tx_ready),.rx_fault(fault),
        .tx_data(data),.tx_valid(consume && valid),.tx_ready(tx_ready));
    always @(posedge clk) if(fault) faults=faults+1;
    initial forever begin
        @(negedge tx);repeat(BIT_TICKS/2) @(posedge clk);
        if(tx!==0) $fatal(1,"UART TX start bit");
        for(b=0;b<8;b=b+1) begin repeat(BIT_TICKS) @(posedge clk);decoded[b]=tx;end
        repeat(BIT_TICKS) @(posedge clk);
        if(tx!==1) $fatal(1,"UART TX stop bit");
        received[count]=decoded;count=count+1;
    end
    task send_byte;
        input [7:0] value;
        input integer ticks;
        input good_stop;
        integer j;
        begin
            @(negedge clk);rx=0;repeat(ticks) @(negedge clk);
            for(j=0;j<8;j=j+1) begin rx=value[j];repeat(ticks) @(negedge clk);end
            rx=good_stop;repeat(ticks) @(negedge clk);rx=1;
            if(!good_stop) repeat(ticks) @(negedge clk);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);resetn=1;
        for(n=0;n<256;n=n+1) send_byte(n,BIT_TICKS,1);
        wait(count==256);
        for(n=0;n<256;n=n+1) if(received[n]!==n[7:0]) $fatal(1,"UART byte mismatch %0d",n);
        send_byte(8'h55,BIT_TICKS*98/100,1);send_byte(8'haa,BIT_TICKS*102/100,1);wait(count==258);
        if(received[256]!==8'h55 || received[257]!==8'haa) $fatal(1,"UART baud tolerance");
        repeat(BIT_TICKS*2) @(negedge clk);consume=0;
        for(n=0;n<131;n=n+1) send_byte("A",BIT_TICKS,1);
        if(faults!=1 || dut.queued!=0 || !dut.discard_line) $fatal(1,"RX overflow was not flushed");
        send_byte(10,BIT_TICKS,1);repeat(10) @(negedge clk);consume=1;
        wait(count==259);if(received[258]!==10) $fatal(1,"Overflow line boundary missing");
        send_byte("Z",BIT_TICKS,1);wait(count==260);if(received[259]!=="Z") $fatal(1,"Overflow recovery failed");
        // Reject a false start, then a broken frame and its suffix until EOL.
        repeat(BIT_TICKS*2) @(negedge clk);old_count=count;
        rx=0;repeat(10) @(negedge clk);rx=1;repeat(BIT_TICKS*2) @(negedge clk);
        if(count!=old_count || faults!=1) $fatal(1,"False start accepted");
        send_byte("X",BIT_TICKS,0);send_byte("Y",BIT_TICKS,1);send_byte(13,BIT_TICKS,1);
        wait(count==261);
        if(received[260]!==13 || faults!=2) $fatal(1,"Frame error did not discard suffix");
        send_byte("Q",BIT_TICKS,1);wait(count==262);
        if(received[261]!=="Q") $fatal(1,"Frame recovery failed");
        $display("PASS [UART 8N1 at 50MHz/9600]: 256 bytes/back-to-back, +/-2%% baud, false start, FIFO overflow/flush/EOL recovery, framing error/suffix discard, independent TX decode");
        $finish;
    end
    initial begin #1000000000;$fatal(1,"UART test timeout");end
endmodule
