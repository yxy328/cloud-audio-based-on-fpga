"""CLS-first control experiments. Production changes require measured PNR savings."""
from pathlib import Path
import hashlib,importlib.util,json,re,shutil,subprocess,sys
import xml.etree.ElementTree as ET
HERE=Path(__file__).resolve().parent
PROJECT=HERE.parent.parent
REPO=PROJECT.parent
DISPLAY=PROJECT/'reports/display_ports_20261026'
GOWIN=Path('E:/130_FPGA_Verilog/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')
IVERILOG=Path('C:/iverilog/bin/iverilog.exe');VVP=Path('C:/iverilog/bin/vvp.exe')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest().upper()
def save(path,obj):path.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def manifest(root):
    result=[]
    for folder in ('pcm5102_pam8403/src','pmod_hub75e/src','build_inputs'):
        result += [{'Path':p.relative_to(root).as_posix(),'SHA256':sha(p)}
                   for p in sorted((root/folder).rglob('*')) if p.is_file()]
    result += [{'Path':n,'SHA256':sha(root/n)} for n in ('pcm5102_pam8403/PCM5102_UNIFIED.gprj','pcm5102_pam8403/tools/build_unified.tcl')]
    return result
def prepare():
    expected=json.loads((DISPLAY/'freeze.json').read_text(encoding='utf-8'))
    assert all(sha(REPO/r['Path'])==r['SHA256'] for r in expected['production_inputs'])
    assert sha(PROJECT/'impl/pnr/PCM5102_UNIFIED.fs')==expected['baseline_fs_sha256']
    baseline=HERE/'baseline';assert not baseline.exists()
    shutil.copytree(DISPLAY/'baseline',baseline)
    shutil.copytree(PROJECT/'sim',baseline/PROJECT.name/'sim',dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('build','__pycache__'))
    save(baseline/'sources.json',manifest(baseline))
    save(HERE/'freeze.json',{'production_inputs':expected['production_inputs'],
         'baseline_audit':expected['baseline_audit'],'baseline_fs_sha256':expected['baseline_fs_sha256'],
         'gowin_sha256':sha(GOWIN)})
    print('Frozen CLS-first baseline: 11387 CLS, 53 BSRAM',flush=True)
def candidate(name):
    target=HERE/name;assert not target.exists()
    shutil.copytree(HERE/'baseline',target,ignore=shutil.ignore_patterns('sources.json','build','__pycache__'))
    return target
def download_decode():
    target=candidate('download_decode')
    path=target/PROJECT.name/'src/downloadable_song.v'
    source=path.read_text(encoding='utf-8')
    start=source.index('    function [6:0] keys_for_mask;')
    end=source.index('    function [7:0] first_pitch;',start)
    source=source[:start]+source[end:]
    start=source.index('    always @* begin\n        covered_mask=0;')
    end=source.index('    wire [7:0] fetched_pitch=',start)
    source=source[:start]+'''    // Fixed pitch comparisons are shared by validation and key decode.
    // Transposing the map avoids seven variable bit writes plus seven
    // independent subtract/range/variable-read networks.
    wire [90:0] map_matches;
    wire [6:0] fetched_keys;
    genvar map_key,map_pitch;
    generate for(map_key=0;map_key<7;map_key=map_key+1)begin: decode_key
        wire [12:0] pitch_hits;
        for(map_pitch=0;map_pitch<13;map_pitch=map_pitch+1)begin: decode_pitch
            assign map_matches[map_key*13+map_pitch]=checked_map[map_key*8 +: 8]==60+map_pitch;
            assign pitch_hits[map_pitch]=fetched[16+map_pitch] && map_matches[map_key*13+map_pitch];
        end
        assign fetched_keys[map_key]=|pitch_hits;
    end
    for(map_pitch=0;map_pitch<13;map_pitch=map_pitch+1)begin: covered_pitch
        wire [6:0] lanes;
        for(map_key=0;map_key<7;map_key=map_key+1)begin: covered_lane
            assign lanes[map_key]=map_matches[map_key*13+map_pitch];
        end
        assign covered_mask[map_pitch]=|lanes;
    end endgenerate
'''+source[end:]
    source=source.replace('    reg [12:0] covered_mask;','    wire [12:0] covered_mask;')
    path.write_text(source,encoding='utf-8',newline='\n')
    save(target/'sources.json',manifest(target))
    print('Prepared download_decode: fixed shared map comparisons',flush=True)
def build(label,kind='all'):
    root=HERE/label;before=manifest(root)
    logpath=root/('build.log' if kind=='all' else 'synthesis.log')
    assert not logpath.exists()
    save(root/'sources.json',before)
    script=root/PROJECT.name/'tools/build_unified.tcl'
    if kind=='syn':
        script=root/PROJECT.name/'tools/synthesis_only.tcl'
        script.write_text((root/PROJECT.name/'tools/build_unified.tcl').read_text(encoding='utf-8').replace('    run all','    run syn'),encoding='utf-8')
    with logpath.open('w',encoding='utf-8') as log:
        p=subprocess.run([str(GOWIN),str(script)],cwd=root/PROJECT.name,stdout=log,stderr=log)
    save(root/('exit.json' if kind=='all' else 'synthesis_exit.json'),{'returncode':p.returncode,'inputs_unchanged':before==manifest(root)})
    print(label,kind,'finished',p.returncode,flush=True)

def adsr_reset():
    target=candidate('adsr_reset')
    path=target/PROJECT.name/'src/adsr_config.v'
    source=path.read_text(encoding='utf-8')
    start=source.index('        if(!resetn) begin')
    end=source.index('        end else begin',start)
    block=source[start:end]
    names=['field','target','times','percentage','a','d','r','s','sa','sd','sr',
           'quotient','remainder','divisor','left','product','multiply_left']
    for name in names:
        block,count=re.subn(r'\b'+name+r'\s*<=[^;]+;','',block)
        assert count==1,(name,count)
    block='''        // IDLE/reset never consumes arithmetic staging data. Each new
        // request loads target/times/percentage/field, and PREPARE/LOAD
        // overwrite every arithmetic operand before its first use. COMMIT
        // follows all four completed fields. Keep visible reset semantics.
'''+block
    source=source[:start]+block+source[end:]
    path.write_text(source,encoding='utf-8',newline='\n')
    save(target/'sources.json',manifest(target))
    print('Prepared adsr_reset: remove only internal staging resets',flush=True)

def parser_staging():
    target=candidate('parser_staging')
    path=target/PROJECT.name/'src/hc05_keymap.v'
    source=path.read_text(encoding='utf-8')
    source=source.replace('    reg [15:0] song_arg0, song_arg1, song_arg2;',
        '''    // Parser fields remain stable throughout SONG_WAIT. The child
    // samples arguments only with song_request, one clock after DECIMAL.
    wire [15:0] song_arg0=(field_count==1) ? accumulator : value0;
    wire [15:0] song_arg1=value1, song_arg2=accumulator;''')
    source=source.replace('    reg [15:0] adsr_a,adsr_d,adsr_s,adsr_r;',
        '''    // ADSR_WAIT preserves these parsed fields until conversion is
    // complete. Restore requests ignore their numeric arguments.
    wire [15:0] adsr_a=value0,adsr_d=value1,adsr_s=value2,adsr_r=accumulator;''')
    counts={}
    for name in ('song_arg0','song_arg1','song_arg2','adsr_a','adsr_d','adsr_s','adsr_r'):
        source,count=re.subn(r'\b'+name+r'\s*<=[^;]+;','',source)
        assert count==2,(name,count)
        counts[name]=count
    path.write_text(source,encoding='utf-8',newline='\n')
    save(target/'change.json',{'removed_shadow_bits':112,'removed_assignments':counts,
         'latency_change':0,'claim':'No CLS saving claimed before complete PNR'})
    save(target/'sources.json',manifest(target))
    print('Prepared parser_staging: use stable parser fields during child request/wait',flush=True)

def physical(label,parent,place):
    root=candidate(label)
    src=HERE/parent/PROJECT.name/'src'
    shutil.copytree(src,root/PROJECT.name/'src',dirs_exist_ok=True)
    script=root/PROJECT.name/'tools/build_unified.tcl'
    text=script.read_text(encoding='utf-8')
    script.write_text(re.sub(r'(-place_option )\d+',lambda m:m[1]+str(place),text),encoding='utf-8',newline='\n')
    save(root/'functional_reference.json',{'parent':parent,'reason':'Identical RTL/ROM/constraints; only physical placement option changes'})
    save(root/'sources.json',manifest(root))
    print('Prepared physical retry',label,flush=True)

def parser_ordered():
    root=candidate('parser_shared')
    path=root/PROJECT.name/'src/hc05_keymap.v'
    source=(HERE/'parser_staging'/PROJECT.name/'src/hc05_keymap.v').read_text(encoding='utf-8')
    source=source.replace('    wire [15:0] song_arg0=(field_count==1) ? accumulator : value0;\n    wire [15:0] song_arg1=value1, song_arg2=accumulator;',
                          '    wire [15:0] song_arg0,song_arg1,song_arg2;')
    source=source.replace('    reg [15:0] accumulator, value0, value1, value2;',
        '''    reg [15:0] accumulator, value0, value1, value2;
    assign song_arg0=(field_count==1) ? accumulator : value0;
    assign song_arg1=value1;
    assign song_arg2=accumulator;''')
    path.write_text(source,encoding='utf-8',newline='\n')
    save(root/'sources.json',manifest(root))
    print('Prepared parser_shared with portable declaration order',flush=True)

def reply_index():
    root=candidate('parser_index')
    path=root/PROJECT.name/'src/hc05_keymap.v'
    source=(HERE/'parser_shared'/PROJECT.name/'src/hc05_keymap.v').read_text(encoding='utf-8')
    marker='    reg [111:0] reply;'
    source=source.replace(marker,marker+'''
    // Keep the complete reply snapshot stationary. Consume only a 5-bit
    // nibble cursor; static punctuation and arbitration do not advance it.
    reg [4:0] reply_digit;
    wire [127:0] reply_digits;
    genvar reply_slot;
    generate for(reply_slot=0;reply_slot<28;reply_slot=reply_slot+1)begin: reply_order
        assign reply_digits[reply_slot*4 +: 4]=reply[111-reply_slot*4 -: 4];
    end endgenerate
    assign reply_digits[127:112]=16'd0;
    wire [3:0] reply_nibble=reply_digits[{reply_digit,2'b00} +: 4];''')
    source=source.replace('hex_char(reply[111:108]) : reply_template;', 'hex_char(reply_nibble) : reply_template;')
    old='''        if(!resetn)reply<=0;
        else if(state==RESPOND)begin
            if(reply_char_ready && !select_log && !select_stream && !select_live &&
               tx_ready && reply_template==8'hff)reply<={reply[107:0],4'd0};
        end else if(state==EXECUTE)begin'''
    assert old in source
    source=source.replace(old,'''        // A dynamic response always snapshots all 112 bits on EXECUTE.
        // With no shift/update outside EXECUTE, invalid old data need no reset.
        if(resetn && state==EXECUTE)begin''')
    marker='    always @(posedge clk) begin\n        if(!resetn) begin\n            note_map<=DEFAULT_MAP;'
    assert marker in source
    source=source.replace(marker,'''    always @(posedge clk)begin
        if(!resetn || state==EXECUTE)reply_digit<=0;
        else if(state==RESPOND && reply_char_ready && !select_log && !select_stream && !select_live &&
                tx_ready && reply_template==8'hff && reply_digit!=28)
            reply_digit<=reply_digit+1'b1;
    end
'''+marker)
    path.write_text(source,encoding='utf-8',newline='\n')
    save(root/'sources.json',manifest(root))
    print('Prepared parser_index: atomic reply snapshot with stationary data and nibble cursor',flush=True)
def audit(label):
    path=PROJECT/'reports/local_reuse_20261025/audit_helpers.py'
    spec=importlib.util.spec_from_file_location('controls_audit',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
    freeze=json.loads((HERE/'freeze.json').read_text(encoding='utf-8'))
    result=m.audit(HERE/label,m.sources(HERE/'baseline'),freeze['baseline_audit']['metrics'])
    project=HERE/label/PROJECT.name
    files=['impl/gwsynthesis/PCM5102_UNIFIED.prj','impl/gwsynthesis/PCM5102_UNIFIED_syn_rsc.xml',
           'impl/pnr/cmd.do','impl/pnr/device.cfg','impl/pnr/PCM5102_UNIFIED.rpt.txt',
           'impl/pnr/PCM5102_UNIFIED.timing_paths','impl/pnr/PCM5102_UNIFIED_tr_content.html']
    result['actual_build_file_hashes']={p:sha(project/p) for p in files if (project/p).exists()}
    result['tool_hashes']={p.name:sha(p) for p in (GOWIN,GOWIN.with_name('GowinSynthesis.exe'),IVERILOG,VVP)}
    result['production_input_count']=len(freeze['production_inputs'])
    save(HERE/label/'audit.json',result)
    print(json.dumps({k:result[k] for k in ('status','metrics','delta_vs_baseline','unrouted_nets','timing')},indent=2))
if __name__=='__main__':
    if sys.argv[1]=='prepare':prepare()
    elif sys.argv[1]=='download':download_decode()
    elif sys.argv[1]=='build':build(sys.argv[2],sys.argv[3] if len(sys.argv)>3 else 'all')
    elif sys.argv[1]=='audit':audit(sys.argv[2])
    elif sys.argv[1]=='adsr':adsr_reset()
    elif sys.argv[1]=='parser':parser_staging()
    elif sys.argv[1]=='physical':physical(sys.argv[2],sys.argv[3],int(sys.argv[4]))
    elif sys.argv[1]=='ordered':parser_ordered()
    elif sys.argv[1]=='index':reply_index()
