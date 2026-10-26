from work import *
out=HERE/'score_app_alt';out.mkdir(exist_ok=False)
s=(HERE/'score_app/ScoreBends.java').read_text(encoding='utf-8')
a=s.index('    public static void checkCapability(');b=s.index('    public List<String> commands()',a)
s=s[:a]+s[b:]
s=s.replace('result.add("SONG_BEGIN,"+song.events.size());','result.add("SONG_BEGIN,"+song.events.size()+(hasBends()?",1":""));')
(out/'ScoreBends.java').write_text(s,encoding='utf-8')
s=(HERE/'score_app/ScoreBendsTest.java').read_text(encoding='utf-8')
s=s.replace('ScoreBends.checkCapability("SONGBEND,1");checks++;bad(()->ScoreBends.checkCapability("SONGBEND,0"));',
            'yes(s.commands().get(0).equals("SONG_BEGIN,6,1"));yes(old.commands().get(0).equals("SONG_BEGIN,2"));')
(out/'ScoreBendsTest.java').write_text(s,encoding='utf-8')
s=(HERE/'integrate_score_app.py').read_text(encoding='utf-8').replace("'score_bend_v1'","'score_bend_alt'")
s=s.replace("('score_bend_protocol_legacy.log','PASS tb_score_legacy')", "('score_alt_regression.log','PASS tb_score_legacy')")
s=s.replace("('score_app_tests.log','4827 checks')", "('score_app_alt_tests.log','4827 checks')")
s=s.replace("HERE/'score_app/", "HERE/'score_app_alt/")
old='''        try{ScoreBends.checkCapability(link.command("SONG_BEGIN,?","SONGBEND"));}
        catch(SppLink.CommandRejectedException e){if(e.response.equals("ERR,CMD"))throw new IOException("该固件不支持曲谱弯音目标，曲谱尚未发送，请使用配套码流");throw e;}
'''
assert old in s;s=s.replace(old,'')
anchor="replace('List<String> commands=selected.commands();','List<String> commands=selectedFile.commands();')"
extra='''
replace('String command=commands.get(i);link.command(command,"OK");',
        'String command=commands.get(i);try{link.command(command,"OK");}catch(SppLink.CommandRejectedException e){if(i==0&&selectedFile.hasBends()&&e.response.equals("ERR,CMD"))throw new IOException("设备未确认曲谱弯音格式，曲谱数据尚未发送，请使用配套码流");throw e;}')
'''
assert anchor in s;s=s.replace(anchor,anchor+extra)
(HERE/'integrate_score_app_alt.py').write_text(s,encoding='utf-8')
print('Staged format-marker phone adapter; production untouched')
