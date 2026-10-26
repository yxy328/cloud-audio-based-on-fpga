"""Adapt only architecture-specific debug seeding in the legacy raster test."""
from work import *
source=(HERE/'baseline'/PROJECT.name/'sim/tb_hub75e_rhythm_display.v').read_text(encoding='utf-8')
source=source.replace('module tb_hub75e_rhythm_display;', 'module tb_hub75e_window_raster;')
start=source.index('            dut.panel_memories[0].memory[k]')
end=source.index('\n        end',start)
source=source[:start]+'''            dut.panel_windows[0].memory[k]=(k*37+11)&127;
            dut.panel_windows[1].memory[k]=(k*37+11)&127;'''+source[end:]
marker='        repeat(133*32*32) @(negedge clk);'
seed=''
for half in range(2):
    block=f'dut.panel_windows[{half}]'
    seed+=f'        {block}.forward_q=0;{block}.bottom_q=0;\n'
    for field,dy in [('q',0),('retained0',1),('retained1',2)]:
        seed+=f'        {block}.{field}=(((dut.head_top+dut.scan_row+{half*32}-{dy})&63)*37+11)&127;\n'
assert marker in source
source=source.replace(marker,seed+marker)
(HERE/'tb_hub75e_window_raster.v').write_text(source,encoding='utf-8')
source=(HERE/'tb_display_window_differential.v').read_text(encoding='utf-8')
source=source.replace('module tb_display_window_differential;', 'module tb_display_window_differential64;')
source=source.replace('parameter integer LEAD=1500;', 'parameter integer LEAD=64;')
(HERE/'tb_display_window_differential64.v').write_text(source,encoding='utf-8')
print('Prepared raster debug seeding and LEAD64 stress variant')
