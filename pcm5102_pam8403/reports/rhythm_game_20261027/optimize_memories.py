from pathlib import Path
R=Path(__file__).resolve().parent/'candidate'/'pcm5102_pam8403'
p=R/'src/hub75e_rhythm_display.v';s=p.read_text(encoding='utf-8')
a=s.index('    // Share the rhythm shader');b=s.index('    always @(posedge clk) begin',a)
s=s[:a]+s[b:]
s=s.replace('            prepared_upper<=0;\n','').replace('                    prepared_upper<=rendered_pixel;\n','')
s=s.replace('status_upper : prepared_upper','status_upper : pixel_rgb(column, upper_y, upper_notes)')
s=s.replace('status_lower : rendered_pixel','status_lower : pixel_rgb(column, lower_y, lower_notes)')
p.write_text(s,encoding='utf-8')
# Separate FIFO data from reset/control so it maps to one physical BSRAM.
p=R/'src/uart_8n1.v';s=p.read_text(encoding='utf-8')
s=s.replace('    reg [7:0] fifo [0:127];','    (* syn_ramstyle="block_ram" *) reg [7:0] fifo [0:127];')
s=s.replace('            prefetched_byte<=0; prefetched_valid<=0;','            prefetched_valid<=0;')
s=s.replace('                    fifo[wr_ptr]<=received_byte; wr_ptr<=wr_ptr+1\'b1;','                    wr_ptr<=wr_ptr+1\'b1;')
s=s.replace('                    prefetched_byte<=fifo[rd_ptr];\n','')
anchor='    reg [9:0] tx_shift;'
s=s.replace(anchor,'''    always @(posedge clk)begin
        if(resetn && !received_error && !overrun)begin
            if(push)fifo[wr_ptr]<=received_byte;
            if(fetch)prefetched_byte<=fifo[rd_ptr];
        end
    end
'''+anchor)
p.write_text(s,encoding='utf-8')
# A stopped song does not award an unfinished hold.
p=R/'src/rhythm_game.v';s=p.read_text(encoding='utf-8').replace('if(event_end || !playing || event_start)finish_event(1);','if(event_end || event_start)finish_event(1);\n                    else if(!playing)finish_event(0);');p.write_text(s,encoding='utf-8')
print('Restored parallel shader; UART FIFO uses spare BSRAM')
