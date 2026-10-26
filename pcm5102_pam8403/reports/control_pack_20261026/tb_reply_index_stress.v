`timescale 1ns/1ps
module tb_reply_index_stress;
    reg clk=0;always #5 clk=~clk;
    reg resetn=0;
    reg [111:0] snapshot=0,saved;
    reg [31:0] random=32'h589d3e71;
    integer trial,n,checks=0;
    hc05_keymap #(.CLK_HZ(1000000),.BAUD(10000)) dut(
        .clk(clk),.resetn(resetn),.rx(1'b1),.visual_snapshot(snapshot));
    hc05_keymap_pack_reference #(.CLK_HZ(1000000),.BAUD(10000)) reference(
        .clk(clk),.resetn(resetn),.rx(1'b1),.visual_snapshot(snapshot));
    initial begin
        repeat(4)@(negedge clk);resetn=1;
        force dut.tx_ready=1;force reference.tx_ready=1;
        force dut.reply_char_ready=1;force reference.reply_char_ready=1;
        force dut.select_log=0;force reference.select_log=0;
        force dut.select_stream=0;force reference.select_stream=0;
        force dut.select_live=0;force reference.select_live=0;
        for(trial=0;trial<100;trial=trial+1)begin
            for(n=0;n<4;n=n+1)begin
                random=random^(random<<13);random=random^(random>>17);random=random^(random<<5);
                snapshot={snapshot[79:0],random};
            end
            if(trial==0)snapshot=0;
            if(trial==1)snapshot={112{1'b1}};
            saved=snapshot;
            force dut.state=1;force reference.state=1;
            force dut.decoded_command=29;force reference.decoded_command=29;
            @(posedge clk);#1;
            if(dut.reply!==saved || reference.reply!==saved || dut.reply_digit!==0)
                $fatal(1,"Atomic reply snapshot failed");
            @(negedge clk);
            force dut.state=2;force reference.state=2;
            for(n=0;n<200;n=n+1)begin
                force dut.select_log=0;force reference.select_log=0;
                force dut.select_stream=0;force reference.select_stream=0;
                force dut.select_live=0;force reference.select_live=0;
                force dut.reply_template=8'hff;force reference.reply_template=8'hff;
                force dut.tx_ready=1;force reference.tx_ready=1;
                case(n%5)
                    1:begin force dut.select_live=1;force reference.select_live=1;end
                    2:begin force dut.select_stream=1;force reference.select_stream=1;end
                    3:begin force dut.select_log=1;force reference.select_log=1;end
                    4:begin force dut.reply_template=8'h41;force reference.reply_template=8'h41;end
                endcase
                if(n%7==0)begin force dut.tx_ready=0;force reference.tx_ready=0;end
                if(n==40)snapshot=~snapshot;
                @(posedge clk);#1;
                if(dut.reply!==saved || dut.reply_nibble!==reference.reply[111:108])
                    $fatal(1,"Reply cursor/shift mismatch trial=%0d cycle=%0d digit=%0d",trial,n,dut.reply_digit);
                checks=checks+1;
                @(negedge clk);
            end
            if(dut.reply_digit!=28)$fatal(1,"Reply saturation coverage missing");
        end
        $display("PASS stationary reply: %0d cycle comparisons, 100 atomic112-bit payloads, all28 positions, zero saturation, punctuation, TX backpressure and log/live/stream arbitration",checks);
        $finish;
    end
endmodule
