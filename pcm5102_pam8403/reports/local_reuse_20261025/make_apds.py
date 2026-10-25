from pathlib import Path
import json, hashlib
H=Path(__file__).resolve().parent
base=H/'baseline/pcm5102_pam8403/src/apds9960_ctrl.v'
dst=H/'apds_serial/pcm5102_pam8403/src/apds9960_ctrl.v'
s=base.read_text(encoding='utf-8-sig')
old='    reg [15:0] acc_u, acc_d, acc_l, acc_r;'
assert s.count(old)==1
s=s.replace(old, old+'''
    // A single local add/subtract path serves FIFO accumulation and all means.
    // No arbitration with either audio engine. Register bank writes stay local.
    reg [1:0] average_channel;
    wire accumulating = state == S_WAIT_FIFO;
    wire [1:0] arithmetic_channel = accumulating ? byte_phase : average_channel;
    reg [15:0] selected_acc;
    reg [7:0] selected_raw;
    always @* begin
        case (arithmetic_channel)
        0: begin selected_acc=acc_u; selected_raw=raw_u; end
        1: begin selected_acc=acc_d; selected_raw=raw_d; end
        2: begin selected_acc=acc_l; selected_raw=raw_l; end
        default: begin selected_acc=acc_r; selected_raw=raw_r; end
        endcase
    end
    wire [15:0] arithmetic_b = accumulating ? {8'd0,i2c_rdata} : ~{8'd0,gflvl_reg};
    // Carry=1 means no borrow for subtraction; replaces four compare paths.
    wire [16:0] arithmetic_result = {1'b0,selected_acc} +
        {1'b0,arithmetic_b} + {16'd0,!accumulating};
    wire [7:0] next_raw = selected_raw + 1'b1;
''')
s=s.replace('            byte_phase <= 2\'d0; dataset_cnt <= 8\'d0;', "            byte_phase <= 2'd0; dataset_cnt <= 8'd0; average_channel <= 0;")
for c in 'udlr':
    old=f'acc_{c} <= acc_{c} + i2c_rdata;'
    assert s.count(old)==1
    s=s.replace(old,f'acc_{c} <= arithmetic_result[15:0];')
s=s.replace('                    state <= S_AVERAGE;', '                    average_channel <= 0; state <= S_AVERAGE;')
start=s.index('                // At most 255 subtractions')
end=s.index('                    start_dir <= 0; end_dir <= 0;',start)
s=s[:start]+'''                // Four serial quotients; at most 4*(255+1)=1024 clocks.
                // Versus the parallel loop, at most 768 additional clocks.
                if (arithmetic_result[16]) begin
                    case (average_channel)
                    0: begin acc_u<=arithmetic_result[15:0]; raw_u<=next_raw; end
                    1: begin acc_d<=arithmetic_result[15:0]; raw_d<=next_raw; end
                    2: begin acc_l<=arithmetic_result[15:0]; raw_l<=next_raw; end
                    3: begin acc_r<=arithmetic_result[15:0]; raw_r<=next_raw; end
                    endcase
                end else if (average_channel != 3) begin
                    average_channel <= average_channel + 1'b1;
                end else begin
'''+s[end:]
dst.write_text(s,encoding='utf-8')
for folder in ['baseline','apds_serial']:
    p=H/folder
    rows=json.loads((p/'sources.json').read_text(encoding='utf-8-sig'))
    changes=[]
    for row in rows:
        rel=row['Path'].replace('\\','/')
        digest=hashlib.sha256((p/rel).read_bytes()).hexdigest().upper()
        if digest != row['SHA256'].upper(): changes.append(rel)
        row['SHA256']=digest
    assert changes==([] if folder=='baseline' else ['pcm5102_pam8403/src/apds9960_ctrl.v']),changes
    (p/'sources.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
    # A separate probe project preserves all APDS ports, matching prior audit.
    probe=p/'probe'; probe.mkdir(exist_ok=False)
    (probe/'probe.gprj').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gowin-fpga-project>
<Project><Template>FPGA</Template><Version>5</Version>
<Device name="GW5A-25A" pn="GW5A-LV25MG121NC1/I0">gw5a25a-002</Device>
<FileList><File path="../pcm5102_pam8403/src/apds9960_ctrl.v" type="file.verilog" enable="1"/></FileList></Project>
''',encoding='utf-8')
    (probe/'build.tcl').write_text('''set here [file dirname [file normalize [info script]]]
cd $here
open_project [file join $here probe.gprj]
set_option -top_module apds9960_ctrl -output_base_name apds_probe
set_option -resource_sharing 1 -retiming 1 -global_freq 50 -enable_dsrm 1
run syn
''',encoding='utf-8')
print('Only apds9960_ctrl.v differs; prepared serial-average A/B probes.')
