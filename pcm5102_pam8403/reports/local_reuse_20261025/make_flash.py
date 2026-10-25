"""Independent B candidate: rotate the existing header, never serially sample live controls."""
from pathlib import Path
import hashlib,json,shutil
H=Path(__file__).resolve().parent
B=H/'baseline'; C=H/'flash_rotate'
rows=json.loads((B/'sources.json').read_text(encoding='utf-8-sig'))
C.mkdir(exist_ok=False)
for row in rows:
    rel=Path(row['Path'].replace('\\','/')); d=C/rel;d.parent.mkdir(exist_ok=True,parents=True)
    assert hashlib.sha256((B/rel).read_bytes()).hexdigest().upper()==row['SHA256'].upper()
    shutil.copyfile(B/rel,d)
p=C/'pcm5102_pam8403/src/take_nor_store.v'
s=p.read_text(encoding='utf-8-sig')
def replace(a,b):
    global s
    assert s.count(a)==1,(a,s.count(a));s=s.replace(a,b)
replace('SELECT_APPLY=25;', 'SELECT_APPLY=25,HEADER_RESTORE=26;')
replace('    reg [127:0] header;', '''    reg [127:0] header;
    reg [2:0] restore_left;
    reg restore_load;''')
replace('''    wire [3:0] selected_header_index=(state==META || state==LOAD_META) ? meta_index : header_index;
    wire [7:0] selected_header_byte=header[selected_header_index*8 +: 8];''',
'''    wire [7:0] selected_header_byte=header[7:0];
    // Visit bytes through a fixed lane. Sixteen rotations restore every bit.
    wire rotate_header=((state==META || state==LOAD_META) && crc_bits==1) ||
        (state==HEADER_RESTORE) ||
        (write_ready && write_valid && operation==2) ||
        (read_valid && (state==HEADER_VERIFY_WAIT || state==COMMIT_VERIFY_WAIT));''')
replace('            header<=0;generation0<=0;', '            header<=0;restore_left<=0;restore_load<=0;generation0<=0;')
replace('            go<=0;abort_spi<=0;boot_done<=0;done<=0;ram_we<=0;',
'''            go<=0;abort_spi<=0;boot_done<=0;done<=0;ram_we<=0;
            if(rotate_header)header<={header[7:0],header[127:8]};''')
replace('''                    if(meta_index==10)state<=LOAD_BEGIN;else meta_index<=meta_index+1'b1;''',
'''                    if(meta_index==10)begin
                        restore_left<=5;restore_load<=1;state<=HEADER_RESTORE;
                    end else meta_index<=meta_index+1'b1;''')
replace('''                    if(meta_index==10)state<=META_DONE;else meta_index<=meta_index+1'b1;''',
'''                    if(meta_index==10)begin
                        restore_left<=5;restore_load<=0;state<=HEADER_RESTORE;
                    end else meta_index<=meta_index+1'b1;''')
replace('''                META_DONE:begin''', '''                HEADER_RESTORE:begin
                    if(restore_left==1)state<=restore_load ? LOAD_BEGIN : META_DONE;
                    else restore_left<=restore_left-1'b1;
                end
                META_DONE:begin''')
p.write_text(s,encoding='utf-8')
changes=[]
for row in rows:
    rel=row['Path'].replace('\\','/');digest=hashlib.sha256((C/rel).read_bytes()).hexdigest().upper()
    if digest!=row['SHA256'].upper():changes.append(rel)
    row['SHA256']=digest
assert changes==['pcm5102_pam8403/src/take_nor_store.v'],changes
(C/'sources.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
for folder in [B,C]:
    probe=folder/'flash_probe';probe.mkdir(exist_ok=False)
    (probe/'probe.gprj').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gowin-fpga-project>
<Project><Template>FPGA</Template><Version>5</Version>
<Device name="GW5A-25A" pn="GW5A-LV25MG121NC1/I0">gw5a25a-002</Device>
<FileList>
<File path="../pcm5102_pam8403/src/take_nor_store.v" type="file.verilog" enable="1"/>
<File path="../pcm5102_pam8403/src/take_spi_transaction.v" type="file.verilog" enable="1"/>
</FileList></Project>
''',encoding='utf-8')
    (probe/'build.tcl').write_text('''set here [file dirname [file normalize [info script]]]
cd $here
open_project [file join $here probe.gprj]
set_option -top_module take_nor_store -output_base_name flash_probe
set_option -resource_sharing 1 -retiming 1 -global_freq 50 -enable_dsrm 1
run syn
''',encoding='utf-8')
print('Flash candidate: only take_nor_store.v differs from verified baseline.')
