from delivery import *

frozen=json.loads((HERE/'base_inputs.json').read_text(encoding='utf-8'))
inputs=[r for r in frozen if r['Path'].startswith(('pcm5102_pam8403/src/','pmod_hub75e/src/'))
        or r['Path'] in ('pcm5102_pam8403/PCM5102_UNIFIED.gprj','pcm5102_pam8403/tools/build_unified.tcl')]
differences=[r['Path'] for r in inputs if not (REPO/r['Path']).exists() or sha(REPO/r['Path'])!=r['SHA256']]
assert not differences, f'Current sources changed since freeze: {differences}'
freeze=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))
assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==freeze['previous_default_fs_sha256']
audit=json.loads((HERE/'build_audit.json').read_text(encoding='utf-8'))
row=next(r for r in audit if r['label']=='apds')
assert row['status']=='validated' and row['delta_vs_baseline']['CLS']<0
comparison=json.loads((HERE/'apds_trace_comparison.json').read_text())
assert all(v['equal'] for v in comparison.values())
source=HERE/'apds/pcm5102_pam8403/src/apds9960_ctrl.v'
destination=PROJECT/'src/apds9960_ctrl.v'
before=sha(destination)
shutil.copy2(source,destination)
write_json(HERE/'integration.json',{
    'time':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
    'selected':'apds','checked_current_inputs':len(inputs),'preexisting_source_changes_preserved':True,
    'changed_production_rtl':['src/apds9960_ctrl.v'],'before_sha256':before,'after_sha256':sha(destination),
    'previous_default_backup':str(HERE/'previous_default'),
    'gesture_timing_note':'See apds_event_timing.json: guard preserved; poll-boundary classification time can change.',
    'three_effects_integrated':False})
print('Integrated only validated APDS arithmetic; preserved all other frozen working-tree inputs')
