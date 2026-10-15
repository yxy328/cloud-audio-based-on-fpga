`timescale 1ns/1ps
// Simulation only: run tools/run_sim.ps1. FPGA synthesis top is top.
// synthesis translate_off
module tb_guitar_top;
    reg clk=0, key=0;
    wire bck,lrck,din;
    top #(.KEY_DEBOUNCE_CYCLES(100)) dut(.clk(clk),.key_s1(key),.key_s2(1'b0),.touch_out(8'd0),
        .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.touch_scl(),.scl(),.sda());
    always #10 clk=~clk;
    integer slot=0, pairs=0, audible=0, tail=0;
    reg started=0;
    reg [15:0] word_value=0,left=0;
    reg signed [15:0] expected=0;
    time last_frame=0;
    integer audio_csv;
    // Export only audio-rate signals so a long decay capture stays small.
    // Run vvp with +long_wave to observe one second of release tail.
    initial begin
        audio_csv = $fopen("sim/build/guitar_samples.csv", "w");
        if (!audio_csv) $fatal(1,"Cannot open guitar_samples.csv");
        $fdisplay(audio_csv,"time_ns,key,pcm");
        $dumpfile("sim/build/guitar_wave.vcd");
        $dumpvars(0, key, dut.audio_sample, dut.u_string.sample,
                     dut.u_string.active, dut.u_string.fill_remaining);
    end
    // Capture the PCM offered to the transmitter before its latch edge.
    always @(posedge clk)
        if(dut.frame_ce) expected <= dut.audio_sample;
    always @(posedge bck) begin
        if(!started && !lrck) begin started=1; slot=0; end
        if(started) begin
            if(slot==0 && !lrck) begin
                if(last_frame!=0 && $time-last_frame!=20480)
                    $fatal(1,"Frame period incorrect");
                last_frame=$time;
            end
            if(slot==0 || slot>16) begin
                if(din!==0) $fatal(1,"I2S padding incorrect");
            end else word_value={word_value[14:0],din};
            if(slot==16) begin
                if(!lrck) begin
                    left=word_value;
                    if(word_value!==expected) $fatal(1,"PCM serialization mismatch");
                end else begin
                    if(word_value!==left) $fatal(1,"Stereo mismatch");
                    pairs=pairs+1;
                    $fdisplay(audio_csv,"%0d,%0d,%0d",$time,key,$signed(left));
                    if(left!=0) begin audible=audible+1; if(!key) tail=tail+1; end
                end
            end
            slot=(slot==31)?0:slot+1;
        end
    end
    initial begin
        #200000; key=1;
        #4000000; key=0;
        #8000000;
        if ($test$plusargs("long_wave")) #1000000000;
        if(pairs<500 || audible<100 || tail<100) $fatal(1,"Missing audio/tail");
        $display("PASS: guitar I2S, %0d stereo frames, %0d tail frames",pairs,tail);
        $fclose(audio_csv);
        $finish;
    end
endmodule
// synthesis translate_on

