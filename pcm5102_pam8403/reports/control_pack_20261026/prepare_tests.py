"""Differential fixtures retain original assertions and compare every output."""
from work import *
spec=importlib.util.spec_from_file_location('statement_parser',PROJECT/'reports/hc05_cls_first_20261026/work.py')
parser=importlib.util.module_from_spec(spec);spec.loader.exec_module(parser)
tokenize=parser.tokenize;paren=parser.paren
label=sys.argv[1];root=HERE/label;project=root/PROJECT.name
download=(HERE/'baseline'/PROJECT.name/'src/downloadable_song.v').read_text(encoding='utf-8').replace(
    'module downloadable_song #(', 'module downloadable_song_pack_reference #(',1)
keymap=(HERE/'baseline'/PROJECT.name/'src/hc05_keymap.v').read_text(encoding='utf-8').replace(
    'module hc05_keymap #(', 'module hc05_keymap_pack_reference #(',1).replace(
    '    downloadable_song #(', '    downloadable_song_pack_reference #(',1)
tests=['tb_downloadable_song','tb_song_time_bound','tb_command_protocol','tb_hc05_extensions',
       'tb_hc05_control_races','tb_fx_protocol','tb_hc05_keymap','tb_hc05_download_current',
       'tb_hc05_take','tb_hc05_adsr','tb_hc05_bend','tb_hc05_visual','tb_hc05_xy']
records=[]
for test in tests:
    fixture=HERE/'baseline'/PROJECT.name/'sim'/(test+'.v')
    if test=='tb_hc05_download_current':fixture=PROJECT/'reports/hc05_cls_first_20261026/fixtures'/fixture.name
    source=fixture.read_text(encoding='utf-8')
    kind='downloadable_song' if test in tests[:2] else 'hc05_keymap'
    reference=download if kind=='downloadable_song' else keymap
    header=reference[:reference.index('\n);')]
    header=re.sub(r'//[^\n]*|/\*[\s\S]*?\*/','',header)
    outputs=[]
    for m in re.finditer(r'\boutput\s+(?:wire|reg)\s*(?:\[[^\]]+\])?\s*([\s\S]*?)(?=\binput\b|\boutput\b|\Z)',header):
        outputs+=re.findall(r'\b[A-Za-z_]\w*\b',m[1])
    tokens=tokenize(source);insertions=[];instances=[]
    for at,t in enumerate(tokens):
        if t[0]!=kind:continue
        start=t[1];i=at+1
        if tokens[i][0]=='#':i=paren(tokens,i+1)
        instance=tokens[i][0];params=source[start+len(kind):tokens[i][1]]
        op=i+1;after=paren(tokens,op)
        ports=source[tokens[op][2]:tokens[after-1][1]]
        pt=tokenize(ports);changes=[];j=0
        while j<len(pt):
            if pt[j][0]=='.' and j+2<len(pt):
                name=pt[j+1][0];end=paren(pt,j+2)
                if name in outputs:changes.append((pt[j+2][2],pt[end-1][1]))
                j=end
            else:j+=1
        for a,b in reversed(changes):ports=ports[:a]+ports[b:]
        ref=instance+'_pack_reference'
        extra='\n    '+kind+'_pack_reference'+params+' '+ref+'('+ports+');\n'
        extra+=f"    always @(negedge {instance}.clk) if({instance}.resetn===1'b1)begin\n"
        for output in outputs:
            extra+=f'        if({instance}.{output} !== {ref}.{output}) $fatal(1,"Pack equivalence: {test} {instance}.{output}");\n'
        extra+='    end\n'
        insertions.append((tokens[after][2],extra));instances.append(instance)
    assert instances,test
    for pos,extra in reversed(insertions):source=source[:pos]+extra+source[pos:]
    for instance in instances:
        # Mirror intentional cursor fast-forward and fault injections.
        source=re.sub(rf'\b(?:force|release)\s+{instance}\.[^;]+;',lambda m:m[0]+'\n            '+m[0].replace(instance+'.',instance+'_pack_reference.'),source)
        source=re.sub(rf'(?m)^(\s*)({instance}\.\w+\s*=(?!=)[^;]+;)',lambda m:m[0]+'\n'+m[1]+m[2].replace(instance+'.',instance+'_pack_reference.'),source)
    name=test+'_pack_equiv'
    source=source.replace('module '+test+';','module '+name+';',1)
    source+='\n'+download+('\n'+keymap if kind=='hc05_keymap' else '')
    (project/'sim'/(name+'.v')).write_text(source,encoding='utf-8')
    records.append({'test':name,'instances':instances,'outputs_per_instance':len(outputs),'fixture_sha256':sha(fixture)})
(project/'sim/downloadable_song_pack_reference.v').write_text(download,encoding='utf-8')
shutil.copy2(HERE/'tb_map_decode_exhaustive.v',project/'sim/tb_map_decode_exhaustive.v')
save(root/'differential_tests.json',records)
print('Generated',len(records),'differential fixtures')
