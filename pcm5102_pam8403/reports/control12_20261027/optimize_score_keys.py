from pathlib import Path
P=Path(__file__).resolve().parent/'candidate/pcm5102_pam8403'
p=P/'src/downloadable_song.v';s=p.read_text(encoding='utf-8')
a=s.index('    function [CONTROL_KEYS-1:0] keys_for_mask;');b=s.index('    function [7:0] first_pitch;',a)
s=s[:a]+s[b:]
s=s.replace('    wire [CONTROL_KEYS-1:0] fetched_keys=keys_for_mask(fetched[28:16],checked_map);',
'''    reg [CONTROL_KEYS-1:0] fetched_keys;
    reg key_decode_busy,key_decode_done;''')
s=s.replace('&& !read_pending) begin', '&& !read_pending && !key_decode_busy && !key_decode_done) begin')
s=s.replace('read_pending<=0;\n        end\n    endtask', 'read_pending<=0;key_decode_busy<=0;key_decode_done<=0;\n        end\n    endtask')
s=s.replace('read_pending<=0; pending_target<=0;', 'read_pending<=0; pending_target<=0;key_decode_busy<=0;key_decode_done<=0;fetched_keys<=0;')
s=s.replace('''            if(read_pending && (state==PRIME || state==RUN)) begin
                case(pending_target)''', '''            key_decode_done<=0;
            if(read_pending && (state==PRIME || state==RUN))begin
                key_decode_busy<=1;map_index<=0;fetched_keys<=0;
            end
            if(key_decode_busy)begin
                if(map_pitch>=60 && map_pitch<=72)fetched_keys[map_index]<=fetched[16+map_pitch-60];
                if(map_index==CONTROL_KEYS-1)begin key_decode_busy<=0;key_decode_done<=1;end
                else map_index<=map_index+1'b1;
            end
            if(key_decode_done && (state==PRIME || state==RUN)) begin
                case(pending_target)''')
s=s.replace('pending_target<=read_target;', 'if(read_enable)pending_target<=read_target;')
assert 'keys_for_mask' not in s
assert 'if(key_decode_done &&' in s
p.write_text(s,encoding='utf-8')
print('One shared mapped-key decoder per fetched score word')
