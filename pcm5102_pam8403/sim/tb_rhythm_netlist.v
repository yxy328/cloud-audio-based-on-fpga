`timescale 1ns/1ps
module tb_rhythm_netlist;
    reg clk=0;always #10 clk=~clk;
    reg rx=1;wire tx,hck,lat,oe,r1,g1,b1,r2,g2,b2;
    wire [4:0] row;tri1 scl,sda,slider_scl,slider_sda;
    top_unified dut(.clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(8'd0),.ir_beam(8'hff),
        .touch_sdo(1'b1),.hc05_rx(rx),.hc05_tx(tx),.audio_rec_cts_n(1'b1),.flash_miso(1'b1),
        .scl(scl),.sda(sda),.slider_scl(slider_scl),.slider_sda(slider_sda),
        .hub_CK(hck),.hub_ST(lat),.hub_OE(oe),.hub_R1(r1),.hub_G1(g1),.hub_B1(b1),.hub_R2(r2),.hub_G2(g2),.hub_B2(b2),
        .hub_A(row[0]),.hub_B(row[1]),.hub_C(row[2]),.hub_D(row[3]),.hub_E(row[4]));
    integer columns=0,rows=0,cycles=0,last_latch=0,bytes=0;
    reg checking=0;reg [255:0] message=0;reg [7:0] value;integer bit_number;
    reg [111:0] decoded;integer digit;reg [7:0] character;
    always @(posedge clk)cycles=cycles+1;
    always @(posedge hck)begin
        if(checking && (^{r1,g1,b1,r2,g2,b2}===1'bx))$fatal(1,"unknown netlist panel output");
        columns=columns+1;
    end
    always @(posedge lat)begin
        if(checking && (columns!=64 || !oe || hck || cycles-last_latch!=133))$fatal(1,"netlist scan period/blank/latch");
        columns=0;last_latch=cycles;rows=rows+1;if(rows==4)checking=1;
    end
    initial forever begin
        @(negedge tx);repeat(2604)@(posedge clk);
        for(bit_number=0;bit_number<8;bit_number=bit_number+1)begin repeat(5208)@(posedge clk);value[bit_number]=tx;end
        repeat(5208)@(posedge clk);if(tx!==1)$fatal(1,"netlist UART stop");message={message[247:0],value};bytes=bytes+1;
    end
    task send_byte;input [7:0] value;integer j;
        begin @(negedge clk);rx=0;repeat(5208)@(negedge clk);
            for(j=0;j<8;j=j+1)begin rx=value[j];repeat(5208)@(negedge clk);end
            rx=1;repeat(5208)@(negedge clk);
        end
    endtask
    initial begin
        wait(rows>=10);send_byte("V");send_byte("I");send_byte("Z");send_byte("?");send_byte(13);
        wait(bytes==32);@(negedge clk);
        if(message[255:240]!=="V," || message[15:0]!==16'h0d0a)$fatal(1,"netlist VIZ framing %0s",message);
        for(digit=0;digit<28;digit=digit+1)begin
            character=message[239-digit*8-:8];
            if(character>=48 && character<=57)decoded[111-digit*4-:4]=character-48;
            else if(character>=65 && character<=70)decoded[111-digit*4-:4]=character-55;
            else $fatal(1,"netlist VIZ hex %0s",message);
        end
        if(decoded!=={4'd2,8'he4,68'd0,1'b1,31'd0})$fatal(1,"netlist VIZ snapshot %0s",message);
        $display("PASS routed netlist: native-wide RAM, 9600-baud command/reply ROM, game settings/BCD snapshot, %0d external 64-column RGB rows",rows);$finish;
    end
    initial if($test$plusargs("scan_only"))begin
        wait(rows==40);@(negedge clk);
        $display("PASS routed netlist scan: 40 external 64-column RGB row pairs, 133-clock period, known pixels and blank/latch ordering");$finish;
    end
    initial begin #50000000;$fatal(1,"netlist timeout");end
endmodule
