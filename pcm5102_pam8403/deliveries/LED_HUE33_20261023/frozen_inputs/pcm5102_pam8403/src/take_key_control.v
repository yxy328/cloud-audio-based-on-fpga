`timescale 1ns/1ps
// K13 play, K14 stop/cancel, K15 record/confirm overwrite, K16 save.
// K14+K16 requests deletion; release both, then K16 confirms it.
// Accepted key states are already filtered by the existing TTP229 reader.
module take_key_control(
    input wire clk,resetn,ready,mode16,
    input wire [3:0] keys,
    input wire [1:0] confirm,
    output reg [2:0] command
);
    reg [3:0] previous;
    reg delete_previous;
    wire [3:0] active=ready && mode16 ? keys : 4'd0;
    wire [3:0] pressed=active & ~previous;
    wire delete_chord=active[1] && active[3];
    always @(posedge clk)begin
        if(!resetn)begin previous<=0;delete_previous<=0;command<=0;end
        else begin
            previous<=active;delete_previous<=delete_chord;command<=0;
            if(delete_chord && !delete_previous)command<=4;
            else if(pressed[1])command<=2;
            else if(!delete_chord)begin
                if(pressed[2])command<=confirm==1 ? 3'd5 : 3'd1;
                else if(pressed[3])command<=confirm==2 ? 3'd5 : 3'd7;
                else if(pressed[0])command<=3;
            end
        end
    end
endmodule
