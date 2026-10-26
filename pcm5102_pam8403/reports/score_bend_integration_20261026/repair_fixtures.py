"""Fix test-only optional ports and migrate the old GPIO audition stimulus."""
from work import *

root=HERE/'candidate'/PROJECT.name
for path in (root/'sim').rglob('*.v'):
    text=path.read_text(encoding='utf-8-sig')
    text=re.sub(r"(?:\.score_ratio\(16'd0\),\.score_keys\(7'd0\),){2,}",
                ".score_ratio(16'd0),.score_keys(7'd0),",text)
    text=re.sub(r"(?:\.arg3\(16'd0\),\.score_min\(16'd8192\),\.score_max\(16'd32768\),){2,}",
                ".arg3(16'd0),.score_min(16'd8192),.score_max(16'd32768),",text)
    if text!=path.read_text(encoding='utf-8-sig'):path.write_text(text,encoding='utf-8',newline='\n')

path=root/'sim/tb_top_audition.v'
text=(HERE/'baseline'/PROJECT.name/'sim/tb_top_audition.v').read_text(encoding='utf-8')
text=text.replace('wire tx,bck,lrck,din,scl;', 'wire tx,bck,lrck,din,scl,sdo;')
text=text.replace('.hc05_rx(rx),.hc05_tx(tx),', '.touch_sdo(sdo),.hc05_rx(rx),.hc05_tx(tx),')
text=text.replace('    // Observe serialized panel pins,', '''    ttp229_model chip(.rst_n(dut.resetn),.scl(scl),.connected(1'b1),.dv(1'b0),
        .stuck_low(1'b0),.keys({8'd0,pads}),.sdo(sdo));
    // Observe serialized panel pins,''')
text=text.replace('        if(scl!==1\'b1) $fatal(1,"Touch direct-mode SCL not HIGH");',
                  '        // The wire-level TTP229 model checks serial clocks and returns pads.')
path.write_text(text,encoding='utf-8',newline='\n')

# Same unchanged baseline must pass the corrected stimulus as well.
shutil.copy2(path,HERE/'baseline'/PROJECT.name/'sim/tb_top_audition_serial_current.v')
path=HERE/'baseline'/PROJECT.name/'sim/tb_top_audition_serial_current.v'
text=path.read_text(encoding='utf-8').replace('module tb_top_audition;','module tb_top_audition_serial_current;')
path.write_text(text,encoding='utf-8')
save(HERE/'fixture_repairs.json',{'production_RTL_changed':False,
    'optional_input_fix':'remove duplicate test-only zero connections left by interrupted preparation',
    'audition_stimulus':'GPIO pads retained as model key state; actual TTP229 serial wires drive DUT',
    'preserved_assertions':'external I2S, 60ms pre-roll, repeated notes, rest/end, held note STOP and map rejection'})
print('Fixed optional test ports and serial audition stimulus')
