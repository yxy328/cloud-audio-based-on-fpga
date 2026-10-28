from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
p=R/'src/hub75e_rhythm_display.v';s=p.read_text(encoding='utf-8')
a=s.index('    function [14:0] digit_bits;');b=s.index('    function [14:0] pixel_rgb;',a);s=s[:a]+s[b:]
for decl in ['        reg [3:0] digit;\n','        reg [14:0] glyph;\n','        reg [5:0] digit_x;\n']:s=s.replace(decl,'')
a=s.index('                if(y<8)begin');b=s.index('            pixel_rgb = {r,g,b};',a)
s=s[:a]+'            end\n'+s[b:]
anchor='    always @(posedge clk) begin\n        if (!resetn) begin\n            state <= S_ROW_PREP;'
code='''    // One-bit synchronous font ROM replaces a combinational glyph shifter.
    wire [5:0] hud_x=visual_read_x;
    wire [3:0] hud_digit;
    wire [2:0] score_digit=3'd5-hud_x[4:2];
    wire [3:0] combo_x=hud_x[3:0]-4'd12;
    wire [1:0] combo_digit=2'd2-combo_x[3:2];
    assign hud_digit=hud_x<24 ? game_score[score_digit*4+:4] :
        hud_x>=44 && hud_x<56 ? game_combo[combo_digit*4+:4] : 4'd15;
    (* syn_romstyle="block_rom" *) reg hud_font[0:511];
    reg hud_bit;
    initial $readmemh("src/rhythm_font.hex",hud_font);
    always @(posedge clk)hud_bit<=hud_font[{hud_digit,scan_row[2:0],hud_x[1:0]}];
    wire [14:0] hud_rgb=!hud_bit ? 15'd0 : column<24 ? {5'd0,5'd24,5'd31} : {5'd31,5'd20,5'd0};
    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_ROW_PREP;'''
assert anchor in s;s=s.replace(anchor,code)
s=s.replace('status_upper : pixel_rgb(column, upper_y, upper_notes)','status_upper : ENABLE_GAME && game_session && upper_y<8 ? hud_rgb : pixel_rgb(column, upper_y, upper_notes)')
p.write_text(s,encoding='utf-8')
digits=['111101101101111','010110010010111','111001111100111','111001111001111','101101111001001','111100111001111','111100111101111','111001001001001','111101111101111','111101111001111']
rom=[]
for d in range(16):
    for y in range(8):
        for x in range(4):rom.append(digits[d][(y-1)*3+x] if d<10 and 1<=y<=5 and x<3 else '0')
(R/'src/rhythm_font.hex').write_text('\n'.join(rom)+'\n',encoding='ascii')
print('512-bit synchronous HUD font generated')
