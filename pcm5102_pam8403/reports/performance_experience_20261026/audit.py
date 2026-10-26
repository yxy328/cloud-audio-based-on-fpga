from work import *
import importlib.util
import re
spec=importlib.util.spec_from_file_location('audit_helpers',PROJECT/'tools/audit_fx_builds.py')
A=importlib.util.module_from_spec(spec);spec.loader.exec_module(A)
base_sources=A.sources(HERE/'base')
base=A.audit(HERE/'base',base_sources,{})
results={'base':base}
for label in ('apds_reuse','tremolo_v1','source_volume_v2','tremolo_v2','tremolo_shared','score_bend','score_bend_v1','score_bend_alt','ir_tuning','ir_tuning_v1','source_expression_v1','touch_tone'):
    if (HERE/label/'sources.json').exists():
        result=A.audit(HERE/label,base_sources,base['metrics'])
        log=(HERE/label/'build.log').read_text(encoding='utf-8',errors='replace')
        missing=re.search(r"(\d+) LUT\(s\).*?unPlaced",log)
        result['unplaced_LUT_equivalents']=int(missing[1]) if missing else 0
        if result['unplaced_LUT_equivalents']:result['status']='placement_failed'
        elif any(m['used']>m['capacity'] for m in result['metrics'].values()):result['status']='resource_failed'
        cls=result['metrics'].get('CLS',{})
        result['CLS_safety_remaining']=cls.get('capacity',0)-cls.get('used',0) if cls else None
        result['passes_35_CLS_reserve']=bool(cls and cls['capacity']-cls['used']>=35)
        result['can_integrate_resource_and_timing_only']=result['status']=='validated' and result['passes_35_CLS_reserve']
        result['actual_build_file_hashes']={name:sha(HERE/label/PROJECT.name/name) for name in (
            'impl/gwsynthesis/PCM5102_UNIFIED.prj','impl/pnr/cmd.do','impl/pnr/device.cfg',
            'impl/pnr/PCM5102_UNIFIED.rpt.txt','impl/pnr/PCM5102_UNIFIED_tr_content.html',
            'impl/pnr/PCM5102_UNIFIED.timing_paths') if (HERE/label/PROJECT.name/name).is_file()}
        results[label]=result
save(HERE/'build_audit.json',results)
for label,r in results.items():
    print(label,r['status'],{k:v['used'] for k,v in r['metrics'].items()},'delta',r['delta_vs_baseline'],
          'unrouted',r['unrouted_nets'],'safety',r.get('CLS_safety_remaining'))
