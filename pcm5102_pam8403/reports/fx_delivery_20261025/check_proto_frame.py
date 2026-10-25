from delivery import *
project=HERE/'fx_apds/pcm5102_pam8403'
suffix=sys.argv[1] if len(sys.argv)>1 else ''
name='tb_fx_proto_frame'+suffix
s=(HERE/'base/pcm5102_pam8403/sim/tb_fx_frame_budget.v').read_text(encoding='utf-8-sig')
s=s.replace('module tb_fx_frame_budget;', 'module '+name+';')
s=s.replace('reg [1:0] effect_at_start', 'reg [2:0] effect_at_start')
s=s.replace('effect_at_start=dut.effect_mode;', 'effect_at_start=dut.tuning_ratio[2:0];')
s=s.replace('effect_at_start!=0', 'effect_at_start==7')
s=s.replace('dut.u_effects.state==4', 'dut.u_effects.state==dut.u_effects.R_MIX')
s=s.replace('max_fx_latency!=5', 'max_fx_latency!=37')
s=s.replace('dut.u_touch_synth.overrun || dut.sensor_overrun',
            'dut.u_touch_synth.overrun || dut.sensor_overrun || dut.u_effects.overrun')
s=s.replace('command("PITCH,,,256\\n",12);', 'command("PITCH,,,256,16391\\n",18);')
s=s.replace('dry/echo/chorus, independent deadlines', 'isolated C+D+R prototype, independent deadlines')
s=s.replace('sim/build/fx_frame_budget.csv', 'sim/build/fx_proto_frame'+suffix+'.csv')
(project/'sim'/ (name+'.v')).write_text(s,encoding='utf-8')
# Register this isolated module in this isolated simulation script only.
p=project/'tools/run_sim.ps1'
s=p.read_text(encoding='utf-8-sig').replace("$rtl += @('sim/i2s_pcm_monitor.v')", "$rtl += @('sim/i2s_pcm_monitor.v','src/audio_fx_minproto.v')")
p.write_text(s,encoding='utf-8')
out=HERE/'functional/fx_apds';out.mkdir(parents=True,exist_ok=True)
with (out/('frame'+suffix+'.log')).open('w',encoding='utf-8') as f:
    r=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-Command',
                      "& './tools/run_sim.ps1' -Tests "+name],cwd=project,stdout=f,stderr=f)
lines=(out/('frame'+suffix+'.log')).read_text().splitlines()
summary=[x for x in lines if x.startswith(('FRAME_','PASS','FATAL'))]
print('\n'.join(summary));write_json(out/('frame'+suffix+'_results.json'),{'exit_code':r.returncode,'summary':summary})
if r.returncode:raise RuntimeError('Prototype frame deadline failed')
