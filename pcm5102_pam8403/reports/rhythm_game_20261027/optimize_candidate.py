from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
def edit(name,old,new):
    p=R/name;s=p.read_text(encoding='utf-8');assert old in s,(name,old[:65]);p.write_text(s.replace(old,new),encoding='utf-8')
edit('src/hub75e_rhythm_display.v','    always @(posedge clk) begin\n        if (!resetn) begin\n            state <= S_ROW_PREP;', '''    // Share the rhythm shader between both panel halves. The shift clock
    // supplies the spare cycle for precomputing the next upper pixel; both
    // output registers still settle one full master clock before hub_CK rises.
    reg [14:0] prepared_upper;
    wire [5:0] render_x=state==S_ROW_PREP ? 6'd0 : state==S_SHIFT ? column+6'd1 : column;
    wire [6:0] render_y=state==S_PIXEL_PREP ? lower_y : upper_y;
    wire [DATA_BITS-1:0] render_notes=state==S_ROW_PREP ? upper_glyph : state==S_PIXEL_PREP ? lower_notes : upper_notes;
    wire [14:0] rendered_pixel=pixel_rgb(render_x,render_y,render_notes);
    always @(posedge clk) begin
        if (!resetn) begin
            prepared_upper<=0;
            state <= S_ROW_PREP;''')
edit('src/hub75e_rhythm_display.v','                S_ROW_PREP: begin','                S_ROW_PREP: begin\n                    prepared_upper<=rendered_pixel;')
edit('src/hub75e_rhythm_display.v','pixel_rgb(column, upper_y, upper_notes)','prepared_upper')
edit('src/hub75e_rhythm_display.v','pixel_rgb(column, lower_y, lower_notes)','rendered_pixel')
edit('src/hub75e_rhythm_display.v','                S_SHIFT: begin','                S_SHIFT: begin\n                    prepared_upper<=rendered_pixel;')
edit('src/key_live_stream.v','    reg [4:0] fifo [0:31];','    (* syn_ramstyle="block_ram" *) reg [4:0] fifo [0:31];')
edit('src/key_live_stream.v','    always @(posedge clk) begin\n        if(!resetn)', '''    // Data is read only after count is nonzero. Invalidating the pointers
    // replaces the unnecessary data reset and permits a physical block RAM.
    always @(posedge clk)begin
        if(pushing)fifo[wr_ptr]<={captured[low_idx],low_idx};
        if(fetch)fifo_q<=fifo[rd_ptr];
    end
    always @(posedge clk) begin
        if(!resetn)''')
edit('src/key_live_stream.v','            fifo_q<=0; wr_ptr<=0;','            wr_ptr<=0;')
edit('src/key_live_stream.v','            if(pushing) fifo[wr_ptr]<={captured[low_idx],low_idx};\n            if(fetch) fifo_q<=fifo[rd_ptr];','')
print('Shader sharing and FIFO block RAM prepared')
