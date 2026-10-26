from work import *
root=HERE/'adsr_reset';project=root/PROJECT.name
out=root/'tests';out.mkdir(exist_ok=True)
reference=out/'adsr_staging_reference.v'
reference.write_text((HERE/'baseline'/PROJECT.name/'src/adsr_config.v').read_text(encoding='utf-8').replace(
    'module adsr_config #(', 'module adsr_config_staging_reference #(',1),encoding='utf-8')
binary=out/'tb_adsr_staging_equivalence.vvp';log=out/'tb_adsr_staging_equivalence.log'
assert not log.exists()
with log.open('w',encoding='utf-8') as stream:
    c=subprocess.run([str(IVERILOG),'-g2001','-s','tb_adsr_staging_equivalence','-o',str(binary),
                      str(HERE/'tb_adsr_staging_equivalence.v'),str(project/'src/adsr_config.v'),str(reference)],stdout=stream,stderr=stream)
    stream.flush()
    r=subprocess.run([str(VVP),str(binary)],stdout=stream,stderr=stream) if c.returncode==0 else c
text=log.read_text(encoding='utf-8')
save(out/'verification.json',{'passed':r.returncode==0 and 'PASS' in text,'returncode':r.returncode,
     'source_sha256':sha(project/'src/adsr_config.v'),'reference_sha256':sha(reference),'log_sha256':sha(log)})
print(text)
raise SystemExit(r.returncode)
