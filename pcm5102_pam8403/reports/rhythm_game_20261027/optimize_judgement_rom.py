from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
p=R/'src/rhythm_game.v';s=p.read_text(encoding='utf-8')
s=s.replace('    reg [7:0] now_ms,due_ms;\n    reg [7:0] age;','''    reg [8:0] now_ms,due_ms;
    wire [8:0] elapsed=now_ms-due_ms;
    wire [7:0] age=elapsed[8] ? 8'hff : elapsed[7:0];''')
s=s.replace('    wire [7:0] perfect_ms=window_ms>>1;\n','')
s=s.replace('reg [7:0] timestamps[0:15];','reg [8:0] timestamps[0:15];')
s=s.replace('    reg phase;\n    reg [7:0] stamp_q;\n    wire [7:0] stamp_age=now_ms-stamp_q;','    reg [1:0] phase;\n    reg [8:0] stamp_q;\n    wire [8:0] stamp_age=now_ms-stamp_q;')
s=s.replace('    wire [7:0] candidate_age=edge_here ? 8\'d0 : stamp_age;\n    wire [7:0] distance=candidate_age>age ? candidate_age-age : age-candidate_age;','''    wire [8:0] candidate_age=edge_here ? 9'd0 : stamp_age;
    wire [8:0] signed_offset=(edge_here ? now_ms : stamp_q)-due_ms;
    (* syn_romstyle="block_rom" *) reg [1:0] judge_rom[0:2047];
    reg [1:0] judge_q;
    reg eligible_q,epoch,read_epoch;
    initial $readmemh("src/rhythm_judge.hex",judge_rom);
    always @(posedge clk)judge_q<=judge_rom[{settings[3:2],signed_offset}];''')
s=s.replace('if(phase && edge_here)','if(phase==1 && edge_here)')
s=s.replace('now_ms<=0;due_ms<=0;age<=0;','now_ms<=0;due_ms<=0;')
s=s.replace('judgement<=0;flash<=0;flash_keys<=0;lane<=0;phase<=0;','judgement<=0;flash<=0;flash_keys<=0;lane<=0;phase<=0;eligible_q<=0;epoch<=0;read_epoch<=0;')
a=s.index('            phase<=~phase;');b=s.index('            // Preserve simultaneous edges',a)
s=s[:a]+'''            phase<=phase==2 ? 0 : phase+1'b1;
            if(phase==1)begin
                read_epoch<=epoch;
                eligible_q<=(edge_here || recent_valid[lane]) && candidate_age<=window_ms;
                if(edge_here)recent_valid[lane]<=1;
                else if(stamp_age>window_ms)recent_valid[lane]<=0;
            end
            if(phase==2)begin
                lane<=lane==KEYS-1 ? 0 : lane+1'b1;
                if(active && !holding && read_epoch==epoch && eligible_q && judge_q[0] &&
                    required_keys[lane] && !matched[lane])begin
                    matched[lane]<=1;recent_valid[lane]<=0;
                    if(!judge_q[1])perfect<=0;
                end
            end
'''+s[b:]
s=s.replace('            if(phase)pending[lane]<=rising[lane];','            if(phase==1)pending[lane]<=rising[lane];')
s=s.replace('                if(active && age!=255)age<=age+1\'b1;\n','')
s=s.replace('required_keys<=event_keys;matched<=0;due_ms<=now_ms;age<=0;','required_keys<=event_keys;matched<=0;due_ms<=now_ms;epoch<=~epoch;')
p.write_text(s,encoding='utf-8')
table=[]
for window in (80,120,160,200):
    for n in range(512):
        signed=n if n<256 else n-512
        table.append((1 if abs(signed)<=window else 0)|(2 if abs(signed)<=window//2 else 0))
(R/'src/rhythm_judge.hex').write_text(''.join(f'{n:x}\n' for n in table),encoding='ascii')
print('Signed early/late judgement ROM generated; 3-clock lane service')
