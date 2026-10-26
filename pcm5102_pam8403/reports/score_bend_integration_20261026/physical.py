from work import *
label=sys.argv[1]
place=int(sys.argv[2])
root=HERE/label
assert not root.exists()
for folder in (PROJECT.name+'/src',PROJECT.name+'/tools',PROJECT.name+'/sim',
               'pmod_hub75e/src','build_inputs'):
    shutil.copytree(HERE/'candidate'/folder,root/folder,
                    ignore=shutil.ignore_patterns('build','__pycache__'))
shutil.copy2(HERE/'candidate'/PROJECT.name/'PCM5102_UNIFIED.gprj',root/PROJECT.name)
path=root/PROJECT.name/'tools/build_unified.tcl'
text=path.read_text(encoding='utf-8')
text=re.sub(r'-place_option \d+', '-place_option '+str(place),text)
path.write_text(text,encoding='utf-8',newline='\n')
mine={row['Path']:row['SHA256'] for row in manifest(root)}
parent={row['Path']:row['SHA256'] for row in manifest(HERE/'candidate')}
assert [name for name in mine if mine[name]!=parent[name]]==['pcm5102_pam8403/tools/build_unified.tcl']
save(root/'functional_reference.json',{'parent':'candidate','only_changed_input':'tools/build_unified.tcl',
    'place_option':place,'reason':'place1 routed but failed setup; prior score D used place2 successfully'})
build(label)
