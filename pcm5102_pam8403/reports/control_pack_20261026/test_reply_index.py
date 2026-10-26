from work import *
root=HERE/'parser_index';project=root/PROJECT.name;out=root/'tests';out.mkdir(exist_ok=True)
binary=out/'tb_reply_index_stress.vvp';log=out/'tb_reply_index_stress.log';assert not log.exists()
files=[HERE/'tb_reply_index_stress.v',project/'sim/tb_hc05_visual_pack_equiv.v']
files += list((project/'src').glob('*.v'))+[root/'pmod_hub75e/src/ttp229_gpio_input.v']
with log.open('w',encoding='utf-8') as stream:
    c=subprocess.run([str(IVERILOG),'-g2001','-s','tb_reply_index_stress','-o',str(binary),*map(str,files)],stdout=stream,stderr=stream)
    stream.flush()
    r=subprocess.run([str(VVP),str(binary)],cwd=project,stdout=stream,stderr=stream) if c.returncode==0 else c
content=log.read_text(encoding='utf-8');print(content)
save(out/'reply_verification.json',{'passed':r.returncode==0 and 'PASS' in content,'returncode':r.returncode,
     'source_sha256':sha(project/'src/hc05_keymap.v'),'log_sha256':sha(log)})
raise SystemExit(r.returncode)
