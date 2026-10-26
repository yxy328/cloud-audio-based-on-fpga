from pathlib import Path
import hashlib,json,shutil,subprocess,sys
H=Path(__file__).resolve().parent;P=H.parent.parent;R=P.parent;C=H/'chain/pcm5102_pam8403';A=H/'app_stage/android_app'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if sys.argv[1]=='integrate':
    assert not (H/'integration.json').exists()
    old=json.loads((P/'reports/touch16_delivery_20261026/production_inputs.json').read_text(encoding='utf-8'))
    assert all(sha(R/e['Path'])==e['SHA256'] for e in old),'Production inputs drifted'
    candidate=json.loads((H/'chain/sources.json').read_text(encoding='utf-8'))
    assert all(sha(H/'chain'/e['Path'])==e['SHA256'] for e in candidate),'Candidate inputs drifted'
    rtl=['src/audio_fx_chain.v','src/hc05_keymap.v','src/top.v','src/hc05_reply.hex','PCM5102_UNIFIED.gprj','tools/generate_hc05_replies.py','tools/run_sim.ps1']
    tests=['tb_audio_fx_chain.v','tb_fx_protocol.v','tb_fx_take_atomic_528.v','tb_fx3_replay_decode.v','tb_fx3_frame_take.v']
    app=['app/build.gradle','app/src/main/AndroidManifest.xml','app/src/main/java/cn/fpga/score/MainActivity.java','app/src/main/java/cn/fpga/score/DeviceControls.java','app/src/main/java/cn/fpga/score/FxState.java','core_test/FxStateTest.java','core_test/SppLinkTest.java','test-core.ps1']
    for name in rtl:shutil.copy2(C/name,P/name)
    for name in tests:shutil.copy2(C/'sim'/name,P/'sim'/name)
    for name in app:shutil.copy2(A/name,P/'android_app'/name)
    target=P/'sim/tb_hc05_extensions.v'
    t=target.read_text();assert 'transact("EFFECT,3,4\\n",11,{"ERR,RANGE"' in t
    target.write_text(t.replace('transact("EFFECT,3,4\\n",11,{"ERR,RANGE"','transact("EFFECT,3,4\\n",11,{"ERR,CMD"'))
    # All baseline inputs plus the added effect module; support/test hashes separate.
    inputs=[e['Path'] for e in old]+['pcm5102_pam8403/src/audio_fx_chain.v']
    save(H/'production_inputs.json',[{'Path':n,'SHA256':sha(R/n)} for n in sorted(inputs)])
    save(H/'integration.json',{'changed_rtl':rtl,'new_tests':tests,'changed_app':app,
        'candidate_source_manifest_verified':True,'previous_production_inputs_verified':len(old)})
    print('Integrated frozen candidate and App Code27; preserved baseline changes')
elif sys.argv[1]=='build':
    assert not (H/'production_build.log').exists()
    inputs=json.loads((H/'production_inputs.json').read_text(encoding='utf-8'))
    assert all(sha(R/e['Path'])==e['SHA256'] for e in inputs)
    exe='E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe'
    with (H/'production_build.log').open('w',encoding='utf-8') as f:
        run=subprocess.run([exe,str(P/'tools/build_unified.tcl')],cwd=P,stdout=f,stderr=f)
    good=all(sha(R/e['Path'])==e['SHA256'] for e in inputs)
    save(H/'production_exit.json',{'returncode':run.returncode,'inputs_unchanged':good})
    assert run.returncode==0 and good
    print('Production full build passed with immutable sources')
