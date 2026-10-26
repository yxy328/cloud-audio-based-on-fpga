from work import *
tests={
'ir_tuning':('tb_ir_tuning_protocol','wire [55:0] tuning;','.ir_tuning(tuning),',[
('BANK,?', 'IRMAP,3C,3E,40,41,43,45,47,48'),('BANK,1,48','OK'),('BANK,8,84','OK'),
('BANK,?','IRMAP,30,3E,40,41,43,45,47,54'),('BANK,0','OK'),('BANK,1','OK'),
('BANK,9,60','ERR,RANGE'),('BANK,2,47','ERR,RANGE'),('BANK,2,85','ERR,RANGE'),('BANK,2,60,1','ERR,CMD')]),
'touch_tone':('tb_touch_tone_protocol','wire touch_tone;','.touch_triangle(touch_tone),.touch_triangle_applied(touch_tone),',[
('TONE,?','TCHTONE,0,0'),('TONE,0,1','OK'),('TONE,7','OK'),('TONE,?','TCHTONE,1,1'),
('TONE,8','ERR,RANGE'),('TONE,1,1','ERR,RANGE'),('TONE,0,2','ERR,RANGE'),('TONE,0,0','OK')]),
'source_expression_v1':('tb_source_expression_protocol','wire [1:0] source_vib;','.source_vibrato(source_vib),.source_vibrato_applied(source_vib),',[
('VIBRATO,?','VIBSRC,0,0'),('VIBRATO,1,1','OK'),('VIBRATO,2,0','OK'),('VIBRATO,?','VIBSRC,1,1'),
('VIBRATO,1','OK'),('VIBRATO,?','VIBSRC,3,3'),('VIBRATO,1,0','OK'),('VIBRATO,?','VIBSRC,2,2'),
('VIBRATO,3,1','ERR,RANGE'),('VIBRATO,2,2','ERR,RANGE'),('VIBRATO,0','OK')])}
for label,(test,decl,ports,commands) in tests.items():
    root=HERE/label;p=root/PROJECT.name
    bench=(PROJECT/'sim/tb_fx_protocol.v').read_text(encoding='utf-8')
    bench=bench.replace('module tb_fx_protocol;',f'module {test};\n    {decl}').replace('.clk(clk),',ports+'.clk(clk),',1)
    snippets='\n'.join(f'        transact("{command}\\n",{len(command)+1},{{"{expected}",8\'d13,8\'d10}});' for command,expected in commands)
    bench=bench.replace('        transact("PING\\n",5,', snippets+'\n        transact("PING\\n",5,')
    bench=bench.replace('fx_protocol_replies.txt',label+'_protocol_replies.txt')
    (p/'sim'/f'{test}.v').write_text(bench,encoding='utf-8')
    with (HERE/(label+'_protocol.log')).open('w',encoding='utf-8') as log:
        result=subprocess.run(['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(p/'tools/run_sim.ps1'),'-Tests',test],cwd=p,stdout=log,stderr=log)
    print(label,result.returncode)
    if result.returncode: print((HERE/(label+'_protocol.log')).read_text(encoding='utf-8',errors='replace')[-2000:])
