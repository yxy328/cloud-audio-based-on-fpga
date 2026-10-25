from delivery import *

root = candidate('display_pair')
path = root / 'pcm5102_pam8403/src/hub75e_rhythm_display.v'
s = path.read_text(encoding='utf-8-sig')
s = s.replace('reg [6:0] head_memory[0:63];', 'reg [13:0] head_memory[0:31];')
s = s.replace('reg [6:0] head_read_q,write_previous;', 'reg [13:0] head_read_q,write_previous;')
s = s.replace('wire [6:0] head_read_value=head_read_forward ? write_previous : head_read_q;',
'''wire [13:0] head_read_pair=head_read_forward ? write_previous : head_read_q;''')
s = s.replace('wire [5:0] head_write_address=head_top+insert_y_s2+scroll_s2;',
'''wire [5:0] head_write_address=head_top+insert_y_s2+scroll_s2;
    wire [6:0] head_read_value=head_write_address[5] ? head_read_pair[13:7] : head_read_pair[6:0];''')
a = s.index('    // The first RAM is the insertion')
b = s.index('    wire head_write=', a)
s = s[:a] + '''    // Physical rows a and a+32 share one 14-bit word. Three display
    // reads each return one upper/lower pair. Together with the insertion
    // RMW memory this is four 32x14 RAMs instead of seven 64x7 RAMs.
    // Both halves retain their own valid bit. External scan timing is unchanged.
''' + s[b:]
s = s.replace('wire head_collision=head_write && head_request==head_write_address;',
'''wire head_collision=head_write && head_request[4:0]==head_write_address[4:0];
    wire [13:0] head_write_pair=head_write_address[5] ?
        {head_write_data,head_read_pair[6:0]} : {head_read_pair[13:7],head_write_data};''')
s = s.replace('if(head_write)head_memory[head_write_address]<=head_write_data;',
              'if(head_write)head_memory[head_write_address[4:0]]<=head_write_pair;')
s = s.replace('head_read_q<=head_memory[head_request];', 'head_read_q<=head_memory[head_request[4:0]];')
s = s.replace('write_previous<=head_write_data;', 'write_previous<=head_write_pair;')
a = s.index('    wire [6:0] panel_heads[0:5];')
b = s.index('    wire [6:0] upper_glyph=', a)
s = s[:a] + '''    wire [6:0] panel_heads[0:5];
    genvar head_port;
    generate for(head_port=0;head_port<3;head_port=head_port+1)begin: panel_memories
        localparam integer DY=head_port;
        (* syn_ramstyle="block_ram" *) reg [13:0] memory[0:31];
        reg [13:0] q;
        reg upper_valid_q,lower_valid_q,forward_q,upper_half_q;
        wire [6:0] upper_requested_y={2'd0,next_scan_row};
        wire [6:0] lower_requested_y=upper_requested_y+7'd32;
        wire [5:0] upper_address=next_head_top+upper_requested_y[5:0]-DY;
        wire [5:0] lower_address={~upper_address[5],upper_address[4:0]};
        wire collision=head_write && upper_address[4:0]==head_write_address[4:0];
        wire upper_collision=head_write && upper_address==head_write_address;
        wire lower_collision=head_write && lower_address==head_write_address;
        wire upper_survives=head_valid[upper_address] && !(scroll && upper_address==wrapped_head);
        wire lower_survives=head_valid[lower_address] && !(scroll && lower_address==wrapped_head);
        wire [13:0] pair_value=forward_q ? write_previous : q;
        always @(posedge clk)begin
            if(head_write)memory[head_write_address[4:0]]<=head_write_pair;
            if(!collision)q<=memory[upper_address[4:0]];
            forward_q<=collision;
            upper_half_q<=upper_address[5];
            upper_valid_q<=resetn && playing && upper_requested_y>=DY && upper_requested_y<=HIT_Y+DY &&
                (upper_collision || upper_survives);
            lower_valid_q<=resetn && playing && lower_requested_y>=DY && lower_requested_y<=HIT_Y+DY &&
                (lower_collision || lower_survives);
        end
        assign panel_heads[head_port]=upper_valid_q ? (upper_half_q ? pair_value[13:7] : pair_value[6:0]) : 7'd0;
        assign panel_heads[head_port+3]=lower_valid_q ? (upper_half_q ? pair_value[6:0] : pair_value[13:7]) : 7'd0;
    end endgenerate
''' + s[b:]
s = s.replace("assign note_rows[debug_row]=head_valid[address] ? head_memory[address] : 7'd0;",
              "assign note_rows[debug_row]=head_valid[address] ? (address[5] ? head_memory[address[4:0]][13:7] : head_memory[address[4:0]][6:0]) : 7'd0;")
path.write_text(s, encoding='utf-8')
(HERE / 'display_pair.diff').write_text(''.join(difflib.unified_diff(
    (HERE/'base/pcm5102_pam8403/src/hub75e_rhythm_display.v').read_text(encoding='utf-8-sig').splitlines(True),
    s.splitlines(True), fromfile='base/hub75e_rhythm_display.v', tofile='display_pair/hub75e_rhythm_display.v')), encoding='utf-8')

# Only adapt the existing directed storage preload to the new physical layout.
# All expected values, independent row model, timing and regression assertions stay frozen.
tb = root / 'pcm5102_pam8403/sim/tb_hub75e_rhythm_display.v'
s = tb.read_text(encoding='utf-8-sig')
a = s.index('        for(k=0;k<64;k=k+1)begin\n            dut.head_memory[k]=')
b = s.index('        repeat(133*32*32)', a)
s = s[:a] + '''        for(k=0;k<32;k=k+1)begin
            dut.head_memory[k]=((((k+32)*37+11)&127)<<7) | ((k*37+11)&127);
            dut.panel_memories[0].memory[k]=dut.head_memory[k];
            dut.panel_memories[1].memory[k]=dut.head_memory[k];
            dut.panel_memories[2].memory[k]=dut.head_memory[k];
        end
''' + s[b:]
tb.write_text(s, encoding='utf-8')
print('Prepared isolated paired-row candidate')
