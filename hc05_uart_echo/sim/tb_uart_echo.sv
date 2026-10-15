`timescale 1ns/1ps
module tb_uart_echo;
    reg clk=0, resetn=0, rx=1;
    always #5 clk=~clk;
    // Accelerated UART: 100 clocks/bit. Also test +/-2% transmitter speed.
    wire tx, valid, framing_error, overflow;
    wire [7:0] data;
    uart_echo #(.CLK_HZ(1_000_000), .BAUD(10000)) dut (
        .clk(clk), .resetn(resetn), .rx(rx), .tx(tx),
        .rx_valid(valid), .rx_data(data),
        .framing_error(framing_error), .overflow(overflow)
    );
    reg [7:0] expected [0:1023];
    integer sent=0, received=0;
    reg [7:0] captured;
    integer b;
    initial begin
        forever begin
            @(negedge tx);
            #500;
            if (tx !== 0) $fatal(1,"Bad TX start");
            for (b=0; b<8; b=b+1) begin
                #1000;
                captured[b]=tx;
            end
            #1000;
            if (tx !== 1) $fatal(1,"Bad TX stop");
            if (received >= sent) $fatal(1,"Unexpected echo");
            if (captured !== expected[received])
                $fatal(1,"Echo %0d: got %02x expected %02x",received,captured,expected[received]);
            received=received+1;
        end
    end
    task send_byte(input [7:0] value, input integer ticks, input bit good_stop);
        integer i;
        begin
            if (good_stop) begin
                expected[sent]=value;
                sent=sent+1;
            end
            rx=0; #(ticks*10);
            for(i=0;i<8;i=i+1) begin rx=value[i]; #(ticks*10); end
            rx=good_stop; #(ticks*10);
        end
    endtask
    task drain;
        begin
            rx=1;
            wait(received==sent);
            #20000;
            if (overflow) $fatal(1,"Unexpected queue overflow");
        end
    endtask
    integer n;
    initial begin
        repeat(10) @(negedge clk);
        resetn=1;
        #1000;
        rx=0; #100; rx=1; #3000; // Short false start must produce no byte.
        for(n=0;n<256;n=n+1) send_byte(n[7:0],100,1);
        drain();
        for(n=0;n<100;n=n+1) send_byte(n[7:0]^8'h55,98,1);
        drain();
        for(n=0;n<100;n=n+1) send_byte(n[7:0]^8'haa,102,1);
        drain();
        if (framing_error) $fatal(1,"Unexpected framing error");
        send_byte(8'h33,100,0);
        rx=0; #30000; // Break: one error, no spurious echoed characters.
        if (!framing_error) $fatal(1,"Missing framing error");
        rx=1; #3000;
        send_byte(8'hc7,100,1);
        drain();
        resetn=0; #100; resetn=1; #1000;
        if (framing_error || overflow || tx!==1) $fatal(1,"Reset failed");
        send_byte(8'h5a,100,1);
        drain();
        $display("PASS: %0d byte echoes; continuous bytes, +/-2%% baud, false start, bad stop, break, recovery, reset",received);
        $finish;
    end
    initial begin #20000000; $fatal(1,"Simulation timeout"); end
endmodule
