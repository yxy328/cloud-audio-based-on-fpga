from work import *
p=HERE/'candidate'/PROJECT.name
text=(p/'sim/tb_top_audition.v').read_text(encoding='utf-8')
text=text.replace('module tb_top_audition;', 'module tb_score_bend_scope;')
text=text.replace('        natural_mapping;', '''        natural_mapping;
        transact("PITCH,8192,32768,65535\\n",23,{"OK",8'd13,8'd10});''')
text=text.replace('transact("SONG_CHORD,0,145,5\\n",19,', 'transact("SONG_CHORD,0,145,8,20000\\n",25,')
text=text.replace('transact("SONG_CHORD,1,145,5\\n",19,', 'transact("SONG_CHORD,1,145,8,12000\\n",25,')
text=text.replace('check_silence(first); // 60ms pre-roll must not leak music.', '''check_silence(first); // 60ms pre-roll must not leak music.
        if(dut.touch_phase_increments[31:0]!==32'd23012828)$fatal(1,"Score target leaked into silent pre-roll");''')
text=text.replace('        chord_start=monitor.pcm_count;', '''        repeat(24)@(posedge dut.frame_ce);@(negedge clk);
        if(dut.touch_phase_increments[31:0]!==32'd28091831)$fatal(1,"First score glide target missing");
        if(dut.u_fsr_pitch_scaler.individual.u_bend.targets[0]!==16'd16384)$fatal(1,"Score overwrote manual target");
        wait(dut.u_keymap.u_download.cur_index==1);repeat(64)@(posedge dut.frame_ce);@(negedge clk);
        if(dut.touch_phase_increments[31:0]!==32'd16855098)$fatal(1,"Second score glide target missing");
        chord_start=monitor.pcm_count;''')
text=text.replace('        #2000000;check_held(7\'h02);check_voice_outputs(7\'h02);', '''        #2000000;check_held(7'h02);check_voice_outputs(7'h02);
        if(dut.touch_phase_increments[31:0]!==32'd23012828)$fatal(1,"STOP failed to restore manual target");''')
text=text.replace('        // Mapping validation still protects audition.', '''        // PLAY supplies silent guidance and must not bend the physical keys.
        transact("PLAY\\n",5,{"OK",8'd13,8'd10});
        skip_visual_wait;
        wait(dut.song_guide_keys==7'h15);repeat(64)@(posedge dut.frame_ce);@(negedge clk);
        if(dut.downloaded_audition || dut.audition_keys!=0 || dut.touch_phase_increments[31:0]!==32'd23012828)
            $fatal(1,"Silent guide applied score pitch");
        transact("STOP\\n",5,{"OK",8'd13,8'd10});
        // Mapping validation still protects audition.''')
text=text.replace('PASS [top audition]:', 'PASS [score bend scope]: distinct event targets, silent pre-roll/PLAY isolation, manual bank retained, STOP restore;')
text=text.replace('#500000000;', '#700000000;')
# Compute constants with an independent wide integer calculation.
text=text.replace("32'd28091831", "32'd"+str((23012828*20000)>>14))
text=text.replace("32'd16855098", "32'd"+str((23012828*12000)>>14))
(p/'sim/tb_score_bend_scope.v').write_text(text,encoding='utf-8')
print('Prepared score scope I2S/serial audition/PLAY/STOP test')
