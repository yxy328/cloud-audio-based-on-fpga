"""Frozen-current RTL versus paired storage, at every external clock edge."""
from delivery import *
import re

fixtures = HERE / 'fixtures'
original = (HERE/'base/pcm5102_pam8403/src/hub75e_rhythm_display.v').read_text(encoding='utf-8-sig')
(fixtures/'display_current_reference.v').write_text(original.replace('module hub75e_rhythm_display #(',
    'module display_current_reference #(', 1), encoding='utf-8')
header = original.split(');', 1)[0]
inputs, outputs, declarations = [], [], []
for line in header.splitlines():
    m = re.match(r'\s*(input|output)\s+(?:wire|reg)\s*((?:signed\s+)?(?:\[[^]]+\]\s*)?)([\w, ]+),?$', line)
    if not m: continue
    direction, shape, names = m.groups()
    for name in names.rstrip(', ').split(','):
        name = name.strip()
        if direction == 'input':
            inputs.append(name)
            declarations.append(f'  reg {shape}{name}=0;')
        else:
            outputs.append(name)
            declarations.append(f'  wire {shape}a_{name}, b_{name};')
instances = []
for module, prefix in [('display_current_reference', 'a'), ('hub75e_rhythm_display', 'b')]:
    connections = [f'.{n}({n})' for n in inputs] + [f'.{n}({prefix}_{n})' for n in outputs]
    instances.append(f'  {module} #(.LEAD_MS(52),.ENABLE_AUDIO_VISUAL(1),.ENABLE_STATUS(1)) {prefix} (\n    '
                     + ',\n    '.join(connections) + '\n  );')
tb = '''`timescale 1ns/1ps
module tb_display_pair;
''' + '\n'.join(declarations + instances) + '''
  always #10 clk=~clk;
  integer cycles=0,checks=0,writes=0,collisions=0,pair_only_collisions=0,scroll_writes=0;
  integer rowprep_writes=0,stop_inflight=0,reset_hits=0;
  reg [31:0] rng=32'h56109aef;
  wire [447:0] rows_a,rows_b;
  genvar j;
  generate for(j=0;j<64;j=j+1)begin: rows
    assign rows_a[j*7+:7]=a.note_rows[j];
    assign rows_b[j*7+:7]=b.note_rows[j];
  end endgenerate
  always @(negedge clk)begin
    cycles=cycles+1;
    rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    resetn=(cycles>5 && cycles%57001!=0);
    playing=(cycles%13007>8);
    ms_tick=rng[0];
    note_spawn=rng[2] | rng[3];
    spawn_keys=rng[22:16];spawn_delay_ms={10'd0,rng[15:10]};
    touch_keys=rng[14:8];guide_keys=rng[21:15];
    touch_mode16=rng[24];all_touch_keys=rng[31:16];physical_keys=rng[15:0];
    sample_ce=(cycles%1024==0);mixed_sample=rng[15:0];
    touch0=rng[15:0]>>>3;touch1=rng[23:8]>>>3;
    sensor_sample=rng[31:16]>>>3;guitar_sample=rng[29:14]>>>3;
    visual_mode=(cycles/140000)%4;
    reference_ratio=rng[4:3];reference_phase=rng[6:5];scope_fsr_gain=16'd1024;
    if(!resetn)reset_hits=reset_hits+1;
    if(!playing && (a.valid_s0||a.valid_s1||a.valid_s2))stop_inflight=stop_inflight+1;
    if(b.head_write)begin
      writes=writes+1;
      if(b.head_collision)collisions=collisions+1;
      if(b.head_collision && a.head_request!=a.head_write_address)pair_only_collisions=pair_only_collisions+1;
      if(b.scroll)scroll_writes=scroll_writes+1;
      if(b.state==0)rowprep_writes=rowprep_writes+1;
    end
  end
  always @(posedge clk)begin
    #1;
    if(resetn)begin
      checks=checks+1;
      if(rows_a!==rows_b)$fatal(1,"logical rows differ at %0d",cycles);
      if(a.upper_notes!==b.upper_notes || a.lower_notes!==b.lower_notes)
        $fatal(1,"row snapshot differs at %0d",cycles);
''' + '\n'.join(f'      if(a_{n}!==b_{n})$fatal(1,"{n} differs at %0d",cycles);' for n in outputs) + '''
    end
    if(cycles==600000)begin
      if(writes<10000 || collisions<10 || pair_only_collisions<10 || scroll_writes<1000 || rowprep_writes<20 || stop_inflight<10)
        $fatal(1,"coverage not reached");
      $display("PASS paired display checks=%0d writes=%0d collisions=%0d opposite_half=%0d scroll_writes=%0d rowprep_writes=%0d stop_inflight=%0d resets=%0d",
        checks,writes,collisions,pair_only_collisions,scroll_writes,rowprep_writes,stop_inflight,reset_hits);
      $finish;
    end
  end
endmodule
'''
(fixtures/'tb_display_pair.sv').write_text(tb, encoding='utf-8')
project=HERE/'display_pair/pcm5102_pam8403'
out=HERE/'functional/display_pair';out.mkdir(parents=True, exist_ok=True)
command=['C:/iverilog/bin/iverilog.exe','-g2001','-s','tb_display_pair','-o',str(out/'differential.vvp'),
         str(fixtures/'tb_display_pair.sv'),str(fixtures/'display_current_reference.v')]
command += [str(p) for p in (project/'src').glob('*.v')]
command += [str(project.parent/'pmod_hub75e/src/ttp229_gpio_input.v')]
with (out/'compile.log').open('w',encoding='utf-8') as f:
    r=subprocess.run(command,cwd=project,stdout=f,stderr=f)
if r.returncode: raise RuntimeError('Differential compile failed')
with (out/'differential.log').open('w',encoding='utf-8') as f:
    r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(out/'differential.vvp')],cwd=project,stdout=f,stderr=f)
text=(out/'differential.log').read_text()
write_json(out/'results.json',{'exit_code':r.returncode,'pass':[s for s in text.splitlines() if s.startswith('PASS')],
    'fixture_sha256':sha(fixtures/'tb_display_pair.sv'),'frozen_reference_sha256':sha(fixtures/'display_current_reference.v')})
print(text)
if r.returncode or 'PASS' not in text: raise RuntimeError('Differential failed')
