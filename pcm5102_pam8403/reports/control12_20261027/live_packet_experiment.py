from pathlib import Path
R=Path(__file__).resolve().parent;P=R/'candidate/pcm5102_pam8403'
old=(P/'src/key_live_stream.v').read_text(encoding='utf-8')
new=old.replace('    reg [63:0] message;\n','')
new=new.replace(' count<=0; message<=0; send_index<=0;', ' count<=0; send_index<=0;')
a='''                    message<={8'd44,tens_byte,ones_byte,8'd44,
                        fifo_q[4] ? 8'd49 : 8'd48,8'd13,8'd10};
'''
assert a in new;new=new.replace(a,'')
a='''                    tx_data<=message[55:48];
                    message<={message[55:0],8'd0};'''
b='''                    // fifo_q is held until the next fetch, so only the
                    // event needs storage. Generate static punctuation at
                    // its byte position instead of shifting a wide packet.
                    case(send_index)
                        0,3:tx_data<=8'd44;
                        1:tx_data<=tens_byte;
                        2:tx_data<=ones_byte;
                        4:tx_data<=fifo_q[4] ? 8'd49 : 8'd48;
                        5:tx_data<=8'd13;
                        6:tx_data<=8'd10;
                        default:tx_data<=0;
                    endcase'''
assert a in new;new=new.replace(a,b)
assert 'message' not in new
for name,source in [('base',old),('serial',new)]:
 d=R/'live_packet_experiment'/name;d.mkdir(parents=True,exist_ok=True)
 (d/'key_live_stream.v').write_text(source,encoding='utf-8')
 g=(R/'score_index_experiment/base/area.gprj').read_text().replace('downloadable_song.v','key_live_stream.v')
 (d/'area.gprj').write_text(g,encoding='utf-8')
 t=(R/'score_index_experiment/base/build.tcl').read_text().replace('downloadable_song','key_live_stream')
 (d/'build.tcl').write_text(t,encoding='utf-8')
(P/'src/key_live_stream.v').write_text(new,encoding='utf-8')
print('Serialize only live key event; generate constant packet bytes in place, preserving backpressure and FIFO capacity')
