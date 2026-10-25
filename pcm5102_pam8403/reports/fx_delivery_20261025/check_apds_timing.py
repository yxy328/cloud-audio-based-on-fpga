from delivery import *
import re

fixture=(HERE/'fixtures/tb_apds_scenarios.sv').read_text()
fixture=fixture.replace('        commands=commands+1;',
    '        commands=commands+1; $display("STAMP_COMMAND %0d %0d",commands,cycles);')
fixture=fixture.replace('        reports=reports+1;',
    '        reports=reports+1; $display("STAMP_EVENT %0d %0d %0d",poll,evaluated,cycles);')
result={}
for active in (100000,93750,93700):
    path=HERE/'fixtures'/f'tb_apds_guard_{active}.sv'
    path.write_text(fixture.replace('AP=100000',f'AP={active}'),encoding='utf-8')
    result[str(active)]={}
    for label in ('base','apds'):
        out=HERE/'functional'/label;exe=out/f'guard_{active}.vvp';log=out/f'guard_{active}.log'
        command=['C:/iverilog/bin/iverilog.exe','-g2012','-DREALTIME','-s','tb_apds_scenarios',
            '-o',str(exe),str(path),str(HERE/label/'pcm5102_pam8403/src/apds9960_ctrl.v')]
        subprocess.run(command,check=True,capture_output=True)
        with log.open('w',encoding='utf-8') as f:
            r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe)],stdout=f,stderr=f)
        lines=log.read_text().splitlines()
        assert r.returncode==0 and any(x.startswith('PASS') for x in lines)
        result[str(active)][label]={
            'classified_guard_cycles': [list(map(int,x.split()[1:])) for x in lines if x.startswith('GUARD')],
            'event_timestamps': [list(map(int,x.split()[1:])) for x in lines if x.startswith('STAMP_EVENT')],
            'command_timestamps': [list(map(int,x.split()[1:])) for x in lines if x.startswith('STAMP_COMMAND')],
            'log_sha256':sha(log)}
    a,b=(result[str(active)][l] for l in ('base','apds'))
    result[str(active)]['classified_timing_delta_cycles']=b['event_timestamps'][-1][-1]-a['event_timestamps'][-1][-1]
    print(active, a['classified_guard_cycles'], b['classified_guard_cycles'],
          'absolute classification delta',result[str(active)]['classified_timing_delta_cycles'])
write_json(HERE/'apds_event_timing.json',result)
