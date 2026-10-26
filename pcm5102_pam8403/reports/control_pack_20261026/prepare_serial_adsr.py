"""Preserve ADSR assertions; replace obsolete GPIO stimulus with serial pads."""
from work import *
source=(HERE/'baseline'/PROJECT.name/'sim/tb_top_runtime_adsr.v').read_text(encoding='utf-8')
source=source.replace('module tb_top_runtime_adsr;', 'module tb_top_runtime_adsr_serial_current;')
source=source.replace('    wire tx,bck,lrck,din,lat;', '    wire tx,bck,lrck,din,lat,touch_scl,touch_sdo;')
source=source.replace('.touch_out(pads),.ir_beam(beams),', '.touch_out(8\'d0),.touch_scl(touch_scl),.touch_sdo(touch_sdo),.ir_beam(beams),')
source=source.replace('    defparam dut.u_gesture.AUDIO_NOTE_FRAMES=400;',
    '''    // Current production is fixed serial16; retain pads as the stimulus
    // for the first eight physical sensor channels, with all ADSR checks.
    ttp229_model chip(.rst_n(dut.resetn),.scl(touch_scl),.connected(1'b1),
        .dv(1'b0),.stuck_low(1'b0),.keys({8'd0,pads}),.sdo(touch_sdo));
    defparam dut.u_gesture.AUDIO_NOTE_FRAMES=400;''')
source=source.replace('wait(dut.resetn);frames(10);','wait(dut.resetn);wait(dut.touch_ready);frames(10);')
for label in ('baseline','adsr_reset'):
    path=HERE/label/PROJECT.name/'sim/tb_top_runtime_adsr_serial_current.v'
    path.write_text(source,encoding='utf-8')
save(HERE/'serial_adsr_fixture.json',{'original_sha256':sha(HERE/'baseline'/PROJECT.name/'sim/tb_top_runtime_adsr.v'),
     'current_fixture_sha256':sha(HERE/'adsr_reset'/PROJECT.name/'sim/tb_top_runtime_adsr_serial_current.v'),
     'changes':['Drive the serial16 TTP229 model instead of removed GPIO pads','Wait for real key readiness'],
     'original_functional_assertions_retained':True})
print('Prepared serial16 top ADSR test on baseline and candidate')
