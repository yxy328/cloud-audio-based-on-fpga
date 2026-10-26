from work import *
root=HERE/'score_bend_v1';p=root/PROJECT.name
bench=(PROJECT/'sim/tb_fx_protocol.v').read_text(encoding='utf-8').replace('module tb_fx_protocol;', 'module tb_score_bend_protocol;')
commands=[('SONG_BEGIN,?','SONGBEND,1'),('SONG_BEGIN,2','OK'),('SONG_CHORD,0,1,10,20000','OK'),
('SONG_CHORD,1,2,10,12000','OK'),('SONG_END','OK'),('SONG_CHORD,0,1,10,1','ERR,STATE'),
('PITCH,15000,20000,4096','OK'),('PLAY','ERR,RANGE'),('PITCH,8192,32768,4096','OK'),
('SONG_BEGIN,1','OK'),('SONG_CHORD,0,1,10,32769','ERR,RANGE'),('SONG_CHORD,0,1,10,8191','ERR,RANGE'),
('SONG_CHORD,0,1,10,20000,0','ERR,CMD'),('SONG_CHORD,0,1,10','OK'),('SONG_END','OK'),
('SONG_BEGIN,?','SONGBEND,1')]
snippets='\n'.join(f'        transact("{command}\\n",{len(command)+1},{{"{expected}",8\'d13,8\'d10}});' for command,expected in commands)
bench=bench.replace('        transact("PING\\n",5,',snippets+'\n        transact("PING\\n",5,').replace('fx_protocol_replies.txt','score_bend_protocol_replies.txt')
(p/'sim/tb_score_bend_protocol.v').write_text(bench,encoding='utf-8')
legacy=(PROJECT/'sim/tb_downloadable_song.v').read_text(encoding='utf-8').replace('tb_downloadable_song','tb_score_legacy')
legacy=legacy.replace('.arg0(arg0),','.arg3(16\'d0),.score_min(16\'d8192),.score_max(16\'d32768),.arg0(arg0),')
(p/'sim/tb_score_legacy.v').write_text(legacy,encoding='utf-8')
manual=(PROJECT/'sim/tb_voice_bend.v').read_text(encoding='utf-8').replace('tb_voice_bend','tb_score_bend_manual_legacy')
manual=manual.replace('dut(.bend_min(',"dut(.score_ratio(16'd0),.score_keys(7'd0),.bend_min(")
(p/'sim/tb_score_bend_manual_legacy.v').write_text(manual,encoding='utf-8')
bench=(PROJECT/'sim/tb_fx3_frame_take.v').read_text(encoding='utf-8').replace('tb_fx3_frame_take','tb_score_bend_frame_take')
old='SONG_CHORD,0,21,1000\n';new='SONG_CHORD,0,21,1000,20000\n'
bench=bench.replace('command("SONG_CHORD,0,21,1000\\n",21);',f'command("SONG_CHORD,0,21,1000,20000\\n",{len(new)});')
bench=bench.replace('integer replay_a=0,replay_b=0,kill_clears=0;', '''integer replay_a=0,replay_b=0,kill_clears=0,replay_curved=0;
    localparam [63:0] EXPECTED_STEP=(64'd23012828*64'd20000)>>14;''')
bench=bench.replace('if(!dut.perf_state[511]', '''if(dut.perf_state[31:0]===EXPECTED_STEP[31:0])replay_curved=replay_curved+1;
        if(!dut.perf_state[511]''')
bench=bench.replace('command("ANALOG,4\\n",9);frames(8);', '''command("BEND_RESET\\n",11);command("PITCH,,,65535\\n",14);frames(64);
        command("ANALOG,4\\n",9);frames(8);''')
bench=bench.replace('command("TAKE_REC\\n",9);frames(80);', '''command("TAKE_REC\\n",9);frames(80);
        command("AUDITION\\n",9);wait(dut.u_keymap.u_download.state==5);
        @(negedge clk);dut.u_keymap.u_download.elapsed_ms=60;
        wait(dut.downloaded_gate);frames(64);
        if(dut.touch_phase_increments[31:0]!==EXPECTED_STEP[31:0])$fatal(1,"Score target not applied through existing bend pipeline got=%d expected=%d",dut.touch_phase_increments[31:0],EXPECTED_STEP);
        if(dut.u_touch_synth.low_steps[31:0]!==EXPECTED_STEP[31:0])$fatal(1,"Audition pitch mismatch");''')
bench=bench.replace('command("TAKE_STOP\\n",10);', 'command("STOP\\n",5);frames(64);command("TAKE_STOP\\n",10);')
bench=bench.replace('if(replay_a<20 || replay_b<20)', 'if(replay_curved<20)$fatal(1,"Missing recorded bent pitch replay frames=%d",replay_curved);\n        if(replay_a<20 || replay_b<20)')
bench=bench.replace('$fclose(csv);$finish;', '$display("PASS score bend target, independent real frame deadlines, and applied bent increments replayed by unchanged TAKE: %0d frames",replay_curved);\n        $fclose(csv);$finish;')
bench=bench.replace('fx3_frame_take.csv','score_bend_frame_take.csv')
(p/'sim/tb_score_bend_frame_take.v').write_text(bench,encoding='utf-8')
print('Prepared D protocol, legacy RAM score, real-frame/TAKE tests')
