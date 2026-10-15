`timescale 1ns/1ps
// Focused PNR diagnostic: keep the exact UART/parser/FIFO primitive netlist.
// Other clocked domains are held in the generated diagnostic copy only.
module tb_hc05_pnr;
    localparam BIT_TICKS=5208;
    reg clk=0; always #10 clk=~clk;
    reg rx=1;
    wire tx;
    reg [255:0] incoming=0,replies[0:3];
    reg [7:0] decoded;
    integer count=0,b,parsed=0,previous_length=0;
    localparam [63:0] LETTERS="PINGMAP?";
    top dut(.clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(8'd0),
        .hc05_rx(rx),.hc05_tx(tx),.i2s_bck(),.i2s_lrck(),.i2s_din(),.touch_scl());
    always @(negedge clk) begin
        if(dut.resetn && dut.\u_keymap/line_error !==0)
            $fatal(1,"PNR parser rejected a valid command byte");
        if(dut.\u_keymap/line_length >previous_length) begin
            $display("PNR parsed letter %0d = %0h",parsed,dut.\u_keymap/line [7:0]);
            if(parsed<8 && dut.\u_keymap/line [7:0]!==LETTERS[(7-parsed)*8 +: 8])
                $fatal(1,"PNR FIFO letter %0d differs from transmitted command",parsed);
            parsed=parsed+1;
        end
        previous_length=dut.\u_keymap/line_length ;
    end
    initial forever begin
        @(negedge tx);repeat(BIT_TICKS/2) @(posedge clk);
        if(tx!==0) $fatal(1,"PNR TX start bit");
        for(b=0;b<8;b=b+1) begin repeat(BIT_TICKS) @(posedge clk);decoded[b]=tx;end
        repeat(BIT_TICKS) @(posedge clk);
        if(tx!==1) $fatal(1,"PNR TX stop bit");
        incoming={incoming[247:0],decoded};
        if(decoded==10) begin
            replies[count]=incoming;count=count+1;
            $display("PNR reply %0d: %0s",count,incoming);incoming=0;
        end
    end
    task send;
        input [255:0] message;
        input integer length;
        integer j,k;
        begin
            for(j=length-1;j>=0;j=j-1) begin
                @(negedge clk);rx=0;repeat(BIT_TICKS) @(negedge clk);
                for(k=0;k<8;k=k+1) begin rx=message[j*8+k];repeat(BIT_TICKS) @(negedge clk);end
                rx=1;repeat(BIT_TICKS) @(negedge clk);
            end
        end
    endtask
    initial begin
        repeat(8) @(negedge clk);
        force dut.power_count=6'd63;
        repeat(8) @(negedge clk);
        // Consecutive lines exercise empty-to-nonempty and prefetched reads.
        send("PING\nMAP?\n",10);
        wait(count>=2);
        if(replies[0]!=={"PONG",8'd13,8'd10} ||
           replies[1]!=={"MAP,60,62,64,65,67,69,71",8'd13,8'd10})
            $fatal(1,"PNR UART/FIFO command replies differ from RTL");
        $display("PASS [PNR UART]: 50MHz/9600, empty FIFO first byte, queued query during reply, actual SDPB primitive and read pointer logic");
        $finish;
    end
    initial begin #100000000;$fatal(1,"PNR UART timeout");end
endmodule
