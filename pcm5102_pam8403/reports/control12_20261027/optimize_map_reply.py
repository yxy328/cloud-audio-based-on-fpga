"""Stream MAP digits through one converter while the UART owns the map."""
from pathlib import Path
P=Path(__file__).resolve().parent/'candidate/pcm5102_pam8403'
p=P/'src/hc05_keymap.v';s=p.read_text(encoding='utf-8')
a=s.index('                CMD_MAP_QUERY: if(CONTROL_KEYS==12)reply<=');b=s.index('                CMD_MAP_SET: reply<=',a)
s=s[:a]+s[b:]
old='    assign reply_byte=reply_template==8\'hff ? hex_char(reply[111:108]) : reply_template;'
new='''    reg [$clog2(CONTROL_KEYS)-1:0] map_reply_key;
    reg map_reply_ones;
    wire [7:0] map_reply_note=note_map[map_reply_key*8+:8];
    wire [3:0] map_reply_digit=map_reply_ones ?
        (map_reply_note<70 ? map_reply_note[3:0]-4'd12 : map_reply_note[3:0]-4'd6) :
        (map_reply_note<70 ? 4'd6 : 4'd7);
    wire advance_payload=state==RESPOND && reply_char_ready && !select_log &&
        !select_stream && !select_live && tx_ready && reply_template==8'hff;
    assign reply_byte=reply_template==8'hff ?
        hex_char(reply_format==19 ? map_reply_digit : reply[111:108]) : reply_template;
    // MAP cannot change while this serialized response owns the command FSM.
    // No parallel BCD bank or MAP arm in the wide reply snapshot mux is needed.
    always @(posedge clk)begin
        if(!resetn)begin map_reply_key<=0;map_reply_ones<=0;end
        else if(state==EXECUTE && decoded_command==CMD_MAP_QUERY)begin map_reply_key<=0;map_reply_ones<=0;end
        else if(advance_payload && reply_format==19)begin
            map_reply_ones<=!map_reply_ones;
            if(map_reply_ones)map_reply_key<=map_reply_key+1'b1;
        end
    end'''
assert old in s;s=s.replace(old,new)
p.write_text(s,encoding='utf-8')
print('Serialized MAP conversion; wire protocol unchanged')
