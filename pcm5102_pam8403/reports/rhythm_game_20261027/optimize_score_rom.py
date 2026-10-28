from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
p=R/'src/rhythm_game.v';s=p.read_text(encoding='utf-8')
s=s.replace('output reg [11:0] combo_bcd,best_bcd,miss_bcd,','output wire [11:0] combo_bcd,best_bcd,miss_bcd,')
s=s.replace('    reg [15:0] hundreds;\n    assign score_bcd={hundreds,8\'d0};','''    // At most 128 chart events: 384 credits of 500 points, combo/miss <=128.
    // Registered ROM conversion replaces four parallel decimal carry chains.
    reg [8:0] credits;
    reg [7:0] combo,best,miss;
    (* syn_romstyle="block_rom" *) reg [23:0] points_rom[0:511];
    (* syn_romstyle="block_rom" *) reg [11:0] stats_rom[0:255];
    reg [23:0] points_q;
    reg [11:0] combo_q,best_q,miss_q;
    initial begin
        $readmemh("src/rhythm_points.hex",points_rom);
        $readmemh("src/rhythm_stats.hex",stats_rom);
    end
    always @(posedge clk)begin
        points_q<=points_rom[credits];
        combo_q<=stats_rom[combo];best_q<=stats_rom[best];miss_q<=stats_rom[miss];
    end
    assign score_bcd=points_q;
    assign combo_bcd=combo_q;assign best_bcd=best_q;assign miss_bcd=miss_q;''')
a=s.index('    function [11:0] inc3;');b=s.index('    task finish_event;',a);s=s[:a]+s[b:]
s=s.replace("hundreds<=add_points(hundreds,(perfect ? 5'd10 : 5'd5)+(long_note ? 5'd5 : 5'd0));","credits<=credits+(perfect ? 9'd2 : 9'd1)+long_note;")
s=s.replace('combo_bcd<=inc3(combo_bcd);','combo<=combo+1\'b1;')
s=s.replace('if(inc3(combo_bcd)>best_bcd)best_bcd<=inc3(combo_bcd);',"if(combo+8'd1>best)best<=combo+8'd1;")
s=s.replace('judgement<=3;combo_bcd<=0;miss_bcd<=inc3(miss_bcd);',"judgement<=3;combo<=0;miss<=miss+1'b1;")
s=s.replace('hundreds<=0;combo_bcd<=0;best_bcd<=0;miss_bcd<=0;','credits<=0;combo<=0;best<=0;miss<=0;')
p.write_text(s,encoding='utf-8')
(R/'src/rhythm_points.hex').write_text(''.join(f'{i*500:06d}\n' for i in range(512)),encoding='ascii')
(R/'src/rhythm_stats.hex').write_text(''.join(f'{i:03d}\n' for i in range(256)),encoding='ascii')
print('Registered BCD ROMs generated; score/state arithmetic reduced')
