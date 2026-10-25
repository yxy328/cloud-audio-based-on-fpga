from delivery import *

for label in ('fx_apds','flash_default'):
    root=candidate(label);project=root/'pcm5102_pam8403'
    shutil.copy2(HERE/'apds/pcm5102_pam8403/src/apds9960_ctrl.v',project/'src/apds9960_ctrl.v')
    if label=='fx_apds':
        for name in ('src/top.v','src/audio_fx_minproto.v','PCM5102_UNIFIED.gprj'):
            shutil.copy2(HERE/'fx_sync/pcm5102_pam8403'/name,project/name)
    else:
        p=project/'src/take_nor_store.v'
        s=p.read_text(encoding='utf-8-sig')
        assert s.count('(* syn_encoding="onehot" *) ')==1
        p.write_text(s.replace('(* syn_encoding="onehot" *) ',''),encoding='utf-8')
print('Prepared independent followups relative to validated current APDS baseline')
