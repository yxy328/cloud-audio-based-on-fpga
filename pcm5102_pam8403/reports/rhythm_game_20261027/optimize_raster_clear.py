from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
p=R/'src/hub75e_rhythm_display.v';s=p.read_text(encoding='utf-8')
s=s.replace('    reg [63:0] head_valid;','''    wire [63:0] head_valid;
    wire initializing,clear_pending;
    wire [5:0] init_row,clear_row;
    wire clear_write;''')
s=s.replace('    assign note_ready = playing;','    assign note_ready = playing && (!ENABLE_GAME || (!initializing && !clear_pending));')
# Check the existing readiness declaration exactly, rather than silently
# leaving a consumer able to submit before the RAM has been cleared.
if 'assign note_ready' not in s:raise RuntimeError('missing ready')
s=s.replace('assign note_ready = playing && !overflow;','assign note_ready = playing && !overflow && (!ENABLE_GAME || (!initializing && !clear_pending));')
s=s.replace('wire head_write=resetn && playing && valid_s2 && insert_y<64;','wire head_write=resetn && playing && valid_s2 && insert_y<64 && (!ENABLE_GAME || !initializing);')
s=s.replace("wire [DATA_BITS-1:0] head_write_data=(head_old_valid ? head_read_value : 7'd0) | keys_s2;","wire [DATA_BITS-1:0] head_write_data=((ENABLE_GAME || head_old_valid) ? head_read_value : {DATA_BITS{1'b0}}) | keys_s2;")
s=s.replace('    wire head_collision=head_write && head_request==head_write_address;','''    assign clear_write=ENABLE_GAME && resetn && playing && !head_write && (initializing || clear_pending);
    wire memory_write=head_write || clear_write;
    wire [5:0] memory_write_address=head_write ? head_write_address : initializing ? init_row : clear_row;
    wire [DATA_BITS-1:0] memory_write_data=head_write ? head_write_data : {DATA_BITS{1'b0}};
    wire head_collision=memory_write && head_request==memory_write_address;''')
a=s.index('    always @(posedge clk)begin\n        if(!resetn || !playing)begin head_top<=0;head_valid<=0;end')
b=s.index('    wire [DATA_BITS-1:0] panel_heads',a)
s=s[:a]+'''    // Legacy mode retains its original valid-bit implementation. Game mode
    // uses idle RAM write slots: initialize all 64 rows, then clear the newly
    // wrapped top row. Note insertion wins over a pending clear. The top ten
    // rows are outside the game lane, so a three-clock deferred clear is hidden.
    generate if(ENABLE_GAME)begin: clear_raster
        reg init_active,pending_clear;
        reg [5:0] init_address,clear_address;
        assign initializing=init_active;assign clear_pending=pending_clear;
        assign init_row=init_address;assign clear_row=clear_address;
        assign head_valid={64{playing && !init_active}};
        always @(posedge clk)begin
            if(!resetn || !playing)begin
                init_active<=1;init_address<=0;pending_clear<=0;clear_address<=0;
            end else begin
                if(clear_write)begin
                    if(init_active)begin
                        init_address<=init_address+1'b1;
                        if(init_address==63)init_active<=0;
                    end else pending_clear<=0;
                end
                if(scroll && !init_active)begin pending_clear<=1;clear_address<=wrapped_head;end
            end
        end
`ifndef SYNTHESIS
        always @(posedge clk)if(resetn && playing && scroll && pending_clear && !clear_write)
            $fatal(1,"game raster millisecond input outran the clear port");
`endif
    end else begin: legacy_valid
        reg [63:0] valid_rows;
        assign head_valid=valid_rows;
        assign initializing=0;assign clear_pending=0;assign init_row=0;assign clear_row=0;
        always @(posedge clk)begin
            if(!resetn || !playing)valid_rows<=0;
            else begin
                if(scroll)valid_rows[wrapped_head]<=0;
                if(head_write)valid_rows[head_write_address]<=1;
            end
        end
    end endgenerate
    always @(posedge clk)begin
        if(!resetn || !playing)head_top<=0;
        else if(scroll)head_top<=wrapped_head;
        if(memory_write)head_memory[memory_write_address]<=memory_write_data;
        if(!head_collision)head_read_q<=head_memory[head_request];
        head_read_forward<=head_collision;
        write_previous<=memory_write_data;
    end
'''+s[b:]
s=s.replace('wire collision=head_write && address==head_write_address;','wire collision=memory_write && address==memory_write_address;')
s=s.replace('if(head_write)memory[head_write_address]<=head_write_data;','if(memory_write)memory[memory_write_address]<=memory_write_data;')
s=s.replace('if (playing && notes[lane] && lane_x','if (playing && (!ENABLE_GAME || y>=TOP_Y) && notes[lane] && lane_x')
# The normal datapath advances three clocks after an accepted spawn. Ignore
# invalid submissions during initialization, but retain every accepted pulse.
s=s.replace('valid_s0 <= note_spawn && spawn_keys != 0;','valid_s0 <= note_spawn && spawn_keys != 0 && (!ENABLE_GAME || !initializing);')
p.write_text(s,encoding='utf-8')
assert '(!initializing && !clear_pending)' in s
p=R/'sim/tb_rhythm_panel.v';s=p.read_text(encoding='utf-8').replace('.visual_mode(2\'d0),.visual_snapshot(snapshot)',".note_ready(ready),.visual_mode(2'd0),.visual_snapshot(snapshot)").replace('    wire [111:0] snapshot;','    wire ready;\n    wire [111:0] snapshot;')
s=s.replace('begin @(negedge clk);spawn_keys=keys;','begin wait(ready);@(negedge clk);spawn_keys=keys;')
p.write_text(s,encoding='utf-8')
print('Game raster uses initialized RAM and deferred clear writes; legacy mode unchanged')
