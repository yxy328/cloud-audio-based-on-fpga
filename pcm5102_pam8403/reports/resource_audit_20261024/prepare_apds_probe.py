"""Isolated exact-width experiment; production RTL is read-only."""
from pathlib import Path
import hashlib
import json

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[1]
source=PROJECT/'src/apds9960_ctrl.v'
original=source.read_text(encoding='utf-8-sig')
candidate=original
changes={
    'reg signed [19:0] delta_ud, delta_lr;':'reg signed [17:0] delta_ud, delta_lr;',
    'wire [19:0] abs_ud = delta_ud[19]':'wire [17:0] abs_ud = delta_ud[17]',
    'wire [19:0] abs_lr = delta_lr[19]':'wire [17:0] abs_lr = delta_lr[17]',
    'reg [19:0] scale_ud, scale_lr;':'reg [17:0] scale_ud, scale_lr;',
    'reg [39:0] ud_strength, lr_strength;':'reg [35:0] ud_strength, lr_strength;',
    'delta_ud[19] ?':'delta_ud[17] ?',
    'delta_lr[19] ?':'delta_lr[17] ?',
}
for old,new in changes.items():
    assert old in candidate,old
    candidate=candidate.replace(old,new)
assert 'delta_ud[19]' not in candidate and 'delta_lr[19]' not in candidate
candidate17=candidate.replace('wire [17:0] abs_ud', 'wire [16:0] abs_ud').replace(
    'wire [17:0] abs_lr', 'wire [16:0] abs_lr').replace(
    'reg [35:0] ud_strength, lr_strength;', 'reg [34:0] ud_strength, lr_strength;')
for name,code in [('apds_baseline',original),('apds_candidate',candidate),('apds_candidate17',candidate17)]:
    folder=HERE/name
    folder.mkdir(exist_ok=False)
    (folder/'apds9960_ctrl.v').write_text(code,encoding='utf-8')
    (folder/'probe.gprj').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gowin-fpga-project>
<Project><Template>FPGA</Template><Version>5</Version>
<Device name="GW5A-25A" pn="GW5A-LV25MG121NC1/I0">gw5a25a-002</Device>
<FileList><File path="apds9960_ctrl.v" type="file.verilog" enable="1"/></FileList></Project>
''',encoding='utf-8')
    (folder/'build.tcl').write_text('''set here [file dirname [file normalize [info script]]]
cd $here
open_project [file join $here probe.gprj]
set_option -top_module apds9960_ctrl -output_base_name apds_probe
set_option -resource_sharing 1 -retiming 1 -global_freq 50 -enable_dsrm 1
run syn
''',encoding='utf-8')
(HERE/'apds9960_ctrl_reference.v').write_text(original.replace('module apds9960_ctrl #(', 'module apds9960_ctrl_reference #(',1),encoding='utf-8')
(HERE/'apds_input_hashes.json').write_text(json.dumps({
    'production_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'candidate_sha256':hashlib.sha256(candidate.encode()).hexdigest(),
    'candidate17_sha256':hashlib.sha256(candidate17.encode()).hexdigest(),
    'changes':changes},indent=2),encoding='utf-8')
print('Prepared APDS exact-width experiment; production source unchanged.')
