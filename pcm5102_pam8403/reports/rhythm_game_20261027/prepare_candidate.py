from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
def edit(name,old,new):
    p=R/name;s=p.read_text(encoding='utf-8');assert old in s,(name,old[:80]);p.write_text(s.replace(old,new),encoding='utf-8')

edit('src/downloadable_song.v','    output reg note_spawn,','    output reg event_start,event_end,\n    output wire [15:0] event_duration,\n    output reg note_spawn,')
edit('src/downloadable_song.v','    assign score_ratio=cur_word[44:29];','    assign score_ratio=cur_word[44:29];\n    assign event_duration=cur_word[15:0];')
edit('src/downloadable_song.v','guide_reset<=1; note_spawn<=0; spawn_keys<=0;','guide_reset<=1; event_start<=0;event_end<=0;note_spawn<=0; spawn_keys<=0;')
edit('src/downloadable_song.v','done<=0; guide_reset<=0; note_spawn<=0;','done<=0; guide_reset<=0; note_spawn<=0;event_start<=0;event_end<=0;')
edit('src/downloadable_song.v','                            guide_keys<=cur_keys;','                            guide_keys<=cur_keys;event_start<=1;')
edit('src/downloadable_song.v','                                    guide_keys<=next_keys;','                                    guide_keys<=next_keys;event_start<=1;event_end<=1;')
# Emit exactly one onset for the first event after pre-roll; repeated guide masks
# do not identify note boundaries, so judging must use an explicit event pulse.
edit('src/downloadable_song.v','                            end else if(next_elapsed_ms>=cur_start_ms) begin','                            end else if(next_elapsed_ms>=cur_start_ms) begin')
edit('src/downloadable_song.v','guide_keys<=cur_keys;event_start<=1;\n                            end','guide_keys<=cur_keys;\n                                if(elapsed_ms<cur_start_ms)event_start<=1;\n                            end')
edit('src/downloadable_song.v','current_finished<=1; guide_keys<=0; current_mask<=0;','current_finished<=1;event_end<=1;guide_keys<=0; current_mask<=0;')

edit('src/hc05_keymap.v','    output wire guide_ms_tick, guide_reset, note_spawn,','    output wire guide_ms_tick, guide_reset, note_spawn,\n    output wire game_event_start,game_event_end,\n    output wire [15:0] game_event_duration,\n    output reg [7:0] game_settings,')
edit('src/hc05_keymap.v','.ms_tick(guide_ms_tick),.guide_reset(guide_reset),.note_spawn(note_spawn),','.ms_tick(guide_ms_tick),.guide_reset(guide_reset),.note_spawn(note_spawn),\n        .event_start(game_event_start),.event_end(game_event_end),.event_duration(game_event_duration),')
edit('tools/generate_hc05_decoder.py','("VIS_SET", "VIS,", 5)','("VIS_SET", "VIS,", None)')
edit('src/hc05_keymap.v','if(line[7:0]>="0" && line[7:0]<="3") begin','if(line_length!=5)begin control_parse<=14;parse_numbers(4,2);end\n                            else if(line[7:0]>="0" && line[7:0]<="3") begin')
edit('src/hc05_keymap.v','                                    default:result(7);','                                    14:if(value0!=0 || accumulator>255)result(2);\n                                       else if(downloaded_playing)result(1);\n                                       else begin game_settings<=accumulator[7:0];remote_mode<=0;visual_write<=1;result(0);end\n                                    default:result(7);')
# Locate the unique reset assignment for visual mode.
p=R/'src/hc05_keymap.v';s=p.read_text(encoding='utf-8');anchor='remote_mode<=0;';pos=s.index(anchor);s=s[:pos]+s[pos:].replace(anchor,anchor+'game_settings<=8\'he4;',1);p.write_text(s,encoding='utf-8')

edit('src/top.v','    wire guide_ms_tick, guide_reset, guide_note_spawn, guide_note_ready;','    wire guide_ms_tick, guide_reset, guide_note_spawn, guide_note_ready;\n    wire game_event_start,game_event_end;\n    wire [15:0] game_event_duration;\n    wire [7:0] game_settings;')
edit('src/top.v','.guide_keys(song_guide_keys),.guide_ms_tick(guide_ms_tick),.guide_reset(guide_reset),','.guide_keys(song_guide_keys),.guide_ms_tick(guide_ms_tick),.guide_reset(guide_reset),\n        .game_event_start(game_event_start),.game_event_end(game_event_end),.game_event_duration(game_event_duration),.game_settings(game_settings),')
edit('src/top.v','hub75e_rhythm_display #(.CONTROL_KEYS(CONTROL_KEYS),','hub75e_rhythm_display #(.ENABLE_GAME(CONTROL_KEYS==12),.CONTROL_KEYS(CONTROL_KEYS),')
edit('src/top.v','.guide_keys(song_guide_keys),.playing(downloaded_playing && !guide_reset),','.guide_keys(song_guide_keys),.playing(downloaded_playing && !guide_reset),\n        .game_event_start(game_event_start && !downloaded_audition),.game_event_end(game_event_end),\n        .game_event_duration(game_event_duration),.game_settings(game_settings & (downloaded_audition ? 8\'h7f : 8\'hff)),')

edit('src/hub75e_rhythm_display.v','    parameter integer LEAD_MS = 1500, CONTROL_KEYS=7,','    parameter integer ENABLE_GAME=0,\n    parameter integer LEAD_MS = 1500, CONTROL_KEYS=7,')
edit('src/hub75e_rhythm_display.v','    input wire playing,','    input wire playing,\n    input wire game_event_start,game_event_end,\n    input wire [15:0] game_event_duration,\n    input wire [7:0] game_settings,')
edit('src/hub75e_rhythm_display.v','    localparam integer TOP_Y = 2;','    localparam integer TOP_Y = ENABLE_GAME ? 10 : 2;\n    localparam integer READ_PORTS=ENABLE_GAME ? 2 : 6;\n    wire game_session,game_holding;\n    wire [23:0] game_score;\n    wire [11:0] game_combo,game_best,game_miss;\n    wire [1:0] game_judge;\n    wire [7:0] game_flash;\n    wire [CONTROL_KEYS-1:0] game_flash_keys;\n    wire [111:0] game_snapshot;\n    generate if(ENABLE_GAME)begin: game\n        rhythm_game #(.KEYS(CONTROL_KEYS)) u_game(\n            .clk(clk),.resetn(resetn),.playing(playing),.ms_tick(ms_tick),\n            .event_start(game_event_start),.event_end(game_event_end),\n            .touch_keys(touch_keys),.event_keys(guide_keys),.event_duration(game_event_duration),\n            .settings(game_settings),.session(game_session),.score_bcd(game_score),\n            .combo_bcd(game_combo),.best_bcd(game_best),.miss_bcd(game_miss),\n            .judgement(game_judge),.flash(game_flash),.flash_keys(game_flash_keys),\n            .holding(game_holding),.snapshot(game_snapshot));\n    end else begin: no_game\n        assign game_session=0;assign game_holding=0;assign game_score=0;\n        assign game_combo=0;assign game_best=0;assign game_miss=0;\n        assign game_judge=0;assign game_flash=0;assign game_flash_keys=0;assign game_snapshot=0;\n    end endgenerate')
edit('src/hub75e_rhythm_display.v','    assign visual_snapshot={4\'d1,','    assign visual_snapshot=ENABLE_GAME && game_settings[7] && visual_active==0 ? game_snapshot : {4\'d1,')
edit('src/hub75e_rhythm_display.v','status_active<=ENABLE_STATUS && !playing;','status_active<=ENABLE_STATUS && !playing && !game_session;')
edit('src/hub75e_rhythm_display.v','wire [CONTROL_KEYS-1:0] panel_heads[0:5];','wire [CONTROL_KEYS-1:0] panel_heads[0:READ_PORTS-1];')
edit('src/hub75e_rhythm_display.v','head_port<6','head_port<READ_PORTS')
edit('src/hub75e_rhythm_display.v','localparam integer OFFSET=(head_port<3 ? 0 : 32);','localparam integer OFFSET=ENABLE_GAME ? head_port*32 : (head_port<3 ? 0 : 32);')
edit('src/hub75e_rhythm_display.v','localparam integer DY=head_port%3;','localparam integer DY=ENABLE_GAME ? 0 : head_port%3;')
edit('src/hub75e_rhythm_display.v','    wire [CONTROL_KEYS-1:0] upper_glyph=panel_heads[0] | panel_heads[1] | panel_heads[2];\n    wire [CONTROL_KEYS-1:0] lower_glyph=panel_heads[3] | panel_heads[4] | panel_heads[5];','    wire [CONTROL_KEYS-1:0] upper_glyph,lower_glyph;\n    generate if(ENABLE_GAME)begin: thin_heads\n        assign upper_glyph=panel_heads[0];assign lower_glyph=panel_heads[1];\n    end else begin: old_heads\n        assign upper_glyph=panel_heads[0] | panel_heads[1] | panel_heads[2];\n        assign lower_glyph=panel_heads[3] | panel_heads[4] | panel_heads[5];\n    end endgenerate')
# Pixel dimensions and hit-line are thin in the candidate. HUD lives above y=10.
edit('src/hub75e_rhythm_display.v','if (y == HIT_Y || y == HIT_Y+1)','if (y == HIT_Y || (!ENABLE_GAME && y == HIT_Y+1))')
edit('src/hub75e_rhythm_display.v','if (playing && notes[lane] && lane_x >= (CONTROL_KEYS==12 ? 1 : 2) && lane_x < (CONTROL_KEYS==12 ? 3 : 7)) begin','if (playing && notes[lane] && lane_x >= (CONTROL_KEYS==12 ? 1 : 2) && lane_x < (CONTROL_KEYS==12 ? (ENABLE_GAME && !game_settings[4] ? 2 : 3) : 7)) begin')
edit('src/hub75e_rhythm_display.v','                    r = 0; g = 24; b = 31;','                    r = 0; g = 24; b = 31;\n                    if(ENABLE_GAME)begin\n                        if(game_settings[1:0]==1)begin r=31;g=16;b=2;end\n                        if(game_settings[1:0]==2)begin r=24;g=24;b=24;end\n                    end')
# Add a tiny shared digit ROM function; BCD values require no binary divider.
edit('src/hub75e_rhythm_display.v','    function [14:0] pixel_rgb;','    function [14:0] digit_bits;\n        input [3:0] digit;\n        begin case(digit)\n        0:digit_bits=15\'b111101101101111;1:digit_bits=15\'b010110010010111;\n        2:digit_bits=15\'b111001111100111;3:digit_bits=15\'b111001111001111;\n        4:digit_bits=15\'b101101111001001;5:digit_bits=15\'b111100111001111;\n        6:digit_bits=15\'b111100111101111;7:digit_bits=15\'b111001001001001;\n        8:digit_bits=15\'b111101111101111;9:digit_bits=15\'b111101111001111;\n        default:digit_bits=0;endcase end\n    endfunction\n    function [14:0] pixel_rgb;')
edit('src/hub75e_rhythm_display.v','        reg [2:0] lane_x;','        reg [2:0] lane_x;\n        reg [3:0] digit;\n        reg [14:0] glyph;\n        reg [5:0] digit_x;')
edit('src/hub75e_rhythm_display.v','            pixel_rgb = {r,g,b};','''            if(ENABLE_GAME && game_session)begin
                if(y>=48 && y<54 && x>=8 && x<56 && game_settings[5] &&
                    game_flash!=0 && game_flash_keys[lane])begin
                    if(game_judge==3)begin r=game_flash[7:3];g=0;b=1;end
                    else if(game_judge==2)begin r=game_flash[7:3];g=game_flash[7:3];b=0;end
                    else begin r=game_flash[7:3];g=game_flash[7:3];b=game_flash[7:3];end
                end
                if(game_holding && guide_keys[lane] && y==56 && x>=8 && x<56)begin r=25;g=0;b=31;end
                if(y<8)begin
                    r=0;g=0;b=0;digit=15;digit_x=x;
                    if(x<24)digit=game_score[(5-x[4:2])*4+:4];
                    else if(x>=44 && x<56)begin digit_x=x-44;digit=game_combo[(2-digit_x[3:2])*4+:4];end
                    glyph=digit_bits(digit);
                    if(y>=1 && y<=5 && digit_x[1:0]<3 && glyph[14-((y-1)*3+digit_x[1:0])])begin
                        if(x<24)begin r=0;g=24;b=31;end
                        else begin r=31;g=20;b=0;end
                    end
                end
            end
            pixel_rgb = {r,g,b};''')
edit('PCM5102_UNIFIED.gprj','<File path="src/downloadable_song.v"','<File path="src/rhythm_game.v" type="file.verilog" enable="1"/><File path="src/downloadable_song.v"')
edit('tools/run_sim.ps1',"'src/hub75e_rhythm_display.v'","'src/rhythm_game.v','src/hub75e_rhythm_display.v'")
print(R)
