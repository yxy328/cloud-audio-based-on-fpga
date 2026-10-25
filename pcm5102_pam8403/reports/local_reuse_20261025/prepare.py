"""Read-only production tree; freeze verified inputs before any RTL experiment."""
from pathlib import Path
import hashlib, json, shutil, xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PROJECT = ROOT / 'pcm5102_pam8403'
OLD = PROJECT / 'sim/build/unified/engine_share_base_20261024'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def dump(p, obj): p.write_text(json.dumps(obj, indent=2), encoding='utf-8')

manifest = json.loads((OLD/'sources.json').read_text(encoding='utf-8-sig'))
for row in manifest:
    rel = Path(row['Path'].replace('\\', '/'))
    assert not rel.is_absolute() and '..' not in rel.parts
    assert sha(OLD/rel) == row['SHA256'].upper(), str(rel)

production = []
for folder in [PROJECT/'src', PROJECT/'sim', PROJECT/'tools', ROOT/'pmod_hub75e/src']:
    for p in folder.rglob('*'):
        if p.is_file() and 'build' not in p.relative_to(folder).parts:
            production.append({'Path': str(p.relative_to(ROOT)).replace('\\','/'), 'SHA256': sha(p)})
for p in [PROJECT/'PCM5102_UNIFIED.gprj', PROJECT/'impl/PCM5102_UNIFIED_process_config.json']:
    production.append({'Path': str(p.relative_to(ROOT)).replace('\\','/'), 'SHA256': sha(p)})
dump(HERE/'production_before.json', production)

for name in ['baseline', 'apds_serial']:
    dst = HERE/name
    dst.mkdir(exist_ok=False)
    for row in manifest:
        rel = Path(row['Path'].replace('\\','/'))
        p = dst/rel
        p.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(OLD/rel, p)
        assert sha(p) == row['SHA256'].upper()
    dump(dst/'sources.json', manifest)

fixtures = HERE/'fixtures'
fixtures.mkdir()
for filename in ['tb_apds_nack.v','tb_i2c_master_bus.v','tb_take_nor_store.v','take_nor_model.v','tb_take_atomic.v','tb_performance_take.v']:
    shutil.copyfile(PROJECT/'sim'/filename, fixtures/filename)
bus=fixtures/'tb_i2c_master_bus.v'
# The current working-tree fixture has two ADS1115 write-extension ports;
# the verified frozen baseline master predates those ports.
bus.write_text(bus.read_text(encoding='utf-8-sig').replace(
    "        .cmd_wdata1(8'h00), .cmd_wlen(1'b0),\n", ''),encoding='utf-8')
ref = (OLD/'pcm5102_pam8403/src/apds9960_ctrl.v').read_text(encoding='utf-8-sig')
(fixtures/'apds_reference.v').write_text(ref.replace('module apds9960_ctrl #(', 'module apds_reference #(', 1), encoding='utf-8')
tools = [Path('C:/iverilog/bin/iverilog.exe'),Path('C:/iverilog/bin/vvp.exe'),Path('E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')]
dump(HERE/'freeze.json', {'baseline':str(OLD), 'manifest_sha256':sha(OLD/'sources.json'), 'verified_inputs':len(manifest), 'tool_hashes':{str(p):sha(p) for p in tools}, 'fixtures':{p.name:sha(p) for p in fixtures.iterdir()}, 'strategy':{'resource_sharing':1,'retiming':1,'global_freq':50,'place_option':0,'route_option':0,'route_maxfan':23}, 'workspace_vs_baseline':[row['Path'] for row in manifest if (ROOT/row['Path']).is_file() and sha(ROOT/row['Path']) != row['SHA256'].upper()]})
print('Frozen and verified',len(manifest),'baseline inputs into two independent trees.')
