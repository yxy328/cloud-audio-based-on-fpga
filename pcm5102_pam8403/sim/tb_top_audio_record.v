`timescale 1ns/1ps
// Real 50MHz audio/I2S/UART timings; only sensor debounce and ADSR shortened.
module tb_top_audio_record;
    reg clk=0;always #10 clk=~clk;
    reg rx=1,cts=0;
    reg [7:0] pads=0,ir=0;
    wire tx,record_tx,bck,lrck,din,hck,lat,oe;
    tri1 scl,sda;
    top #(.ENABLE_USB_AUDIO_RECORD(1),.HC05_BAUD(500000),.TOUCH_STARTUP_US(100),.TOUCH_DEBOUNCE_MS(1),
        .ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),.TOUCH_ADSR_RELEASE_SAMPLES(16),
        .FSR_ENABLE(0),.IR_FILTER_CYCLES(100),.GUITAR_STRING_LENGTH(16)) dut(
        .clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(pads),.touch_sdo(1'b1),
        .ir_beam(ir),.hc05_rx(rx),.hc05_tx(tx),.audio_rec_cts_n(cts),.audio_rec_tx(record_tx),
        .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.scl(scl),.sda(sda),
        .hub_CK(hck),.hub_ST(lat),.hub_OE(oe));
    i2s_pcm_monitor #(.PCM_MIN(-32768),.PCM_MAX(32767),.CAPTURE_FILE("sim/build/audio_record_top_i2s.csv")) monitor(
        .bck(bck),.lrck(lrck),.din(din));
    reg [15:0] expected[0:4095];
    integer i2s_index[0:4095];
    integer count=0,frames=0,nonzero=0,columns=0,latches=0;
    always @(posedge hck)if(dut.resetn)columns=columns+1;
    always @(posedge lat)if(dut.resetn)begin
        if(columns!=64 || oe!==1)$fatal(1,"Panel scan affected by recorder");
        columns=0;latches=latches+1;
    end
    always @(posedge clk)if(dut.resetn && dut.frame_ce)begin
        frames=frames+1;
        if(dut.u_touch_synth.overrun || dut.sensor_overrun)$fatal(1,"TDM deadline");
        if(dut.legacy_pcm.u_audio_record.capturing && !dut.audio_rec_stop)begin
            expected[count]=dut.audio_sample;i2s_index[count]=monitor.pcm_count;
            if(dut.audio_sample!=0)nonzero=nonzero+1;
            count=count+1;
        end
    end
    integer replies=0,b;
    reg [255:0] incoming=0,last_reply=0;
    reg [7:0] data;
    initial forever begin
        @(negedge tx);repeat(50)@(posedge clk);
        for(b=0;b<8;b=b+1)begin repeat(100)@(posedge clk);data[b]=tx;end
        repeat(100)@(posedge clk);if(tx!==1)$fatal(1,"Control stop bit");
        incoming={incoming[247:0],data};
        if(data==10)begin last_reply=incoming;incoming=0;replies=replies+1;end
    end
    task command;
        input [255:0] message;
        input integer length;
        integer c,k,target;
        begin target=replies+1;
            for(c=length-1;c>=0;c=c-1)begin
                @(negedge clk);rx=0;repeat(100)@(negedge clk);
                for(k=0;k<8;k=k+1)begin rx=message[c*8+k];repeat(100)@(negedge clk);end
                rx=1;repeat(100)@(negedge clk);
            end
            wait(replies==target);
            if(last_reply!=={"OK",8'd13,8'd10})$fatal(1,"Command %0s got %0s",message,last_reply);
        end
    endtask
    task wait_frames;input integer n;integer target;begin target=frames+n;wait(frames>=target);@(negedge clk);end endtask
    reg [7:0] bytes[0:16383];
    integer received=0,bitno;
    reg [7:0] byte_in;
    initial forever begin
        @(negedge record_tx);repeat(12)@(posedge clk);
        for(bitno=0;bitno<8;bitno=bitno+1)begin repeat(25)@(posedge clk);byte_in[bitno]=record_tx;end
        repeat(25)@(posedge clk);if(record_tx!==1)$fatal(1,"Audio stop bit");
        bytes[received]=byte_in;received=received+1;
    end
    function [15:0] get16;input integer i;begin get16={bytes[i+1],bytes[i]};end endfunction
    function [31:0] get32;input integer i;begin get32={bytes[i+3],bytes[i+2],bytes[i+1],bytes[i]};end endfunction
    function [15:0] crc16;
        input integer offset,length;integer j,k;reg [15:0] c;
        begin c=65535;for(j=0;j<length;j=j+1)begin c=c^{bytes[offset+j],8'd0};
            for(k=0;k<8;k=k+1)c=c[15]?(c<<1)^16'h1021:c<<1;end crc16=c;end
    endfunction
    integer offset,length,sequence,samples_seen,j,kind,file_id;
    initial begin
        wait(dut.touch_ready);wait_frames(3);
        command("AREC_START,4660\n",16);
        pads=7;wait(dut.touch_keys==7);wait_frames(100);
        ir=8'h03;wait_frames(100);
        // APDS optical classification is outside this digital recording test.
        // Inject a classified gesture; synthesis and recording remain real RTL.
        force dut.u_gesture.init_done=1'b1;
        force dut.u_gesture.dir_evaluated=1'b1;
        force dut.u_gesture.start_dir=3'd1;
        force dut.u_gesture.end_dir=3'd2;
        @(negedge clk);force dut.u_gesture.gesture_valid=1'b1;
        @(negedge clk);force dut.u_gesture.gesture_valid=1'b0;
        wait_frames(40);
        if(dut.sensor_voice_count<3)$fatal(1,"IR/gesture voices not active");
        command("GUITAR\n",7);wait_frames(100);
        command("EFFECT,2,8\n",11);command("VOLUME,8\n",9);
        cts=1;wait_frames(70);cts=0;wait_frames(130);
        pads=0;ir=0;wait_frames(100);
        command("AREC_STOP\n",10);wait(!dut.audio_rec_busy);wait_frames(3);
        if(dut.audio_rec_overflow || count<650 || count>2000 || nonzero<300 || latches<64)
            $fatal(1,"Missing live activity/scan or capture overflow: count=%0d nonzero=%0d",count,nonzero);
        offset=0;sequence=0;samples_seen=0;kind=0;
        while(offset<received)begin
            if({bytes[offset],bytes[offset+1],bytes[offset+2],bytes[offset+3]}!=="FAR1")$fatal(1,"Magic");
            length=get16(offset+6);kind=bytes[offset+4];
            if(bytes[offset+5]!=0 || get16(offset+8)!=sequence || get16(offset+10)!=4660 || get32(offset+12)!=samples_seen)
                $fatal(1,"Header");
            if(crc16(offset,16+length)!==get16(offset+16+length))$fatal(1,"CRC");
            if(sequence==0)begin if(kind!=1 || length!=8)$fatal(1,"Start");end
            else if(kind==2)begin
                for(j=0;j<length/2;j=j+1)begin
                    if(get16(offset+16+2*j)!==expected[samples_seen])$fatal(1,"Uploaded PCM mismatch %0d",samples_seen);
                    if(monitor.pcm[i2s_index[samples_seen]]!==$signed(expected[samples_seen]))
                        $fatal(1,"External I2S mismatch %0d index %0d got %0d expected %0d",samples_seen,i2s_index[samples_seen],monitor.pcm[i2s_index[samples_seen]],$signed(expected[samples_seen]));
                    samples_seen=samples_seen+1;
                end
            end else if(kind==3)begin if(length!=4 || get32(offset+16)!=0 || offset+22!=received)$fatal(1,"End");end
            else $fatal(1,"Type");
            offset=offset+18+length;sequence=sequence+1;
        end
        if(kind!=3 || samples_seen!=count)$fatal(1,"Incomplete upload");
        file_id=$fopen("sim/build/audio_record_top.bin","wb");
        for(j=0;j<received;j=j+1)$fwrite(file_id,"%c",bytes[j]);$fclose(file_id);
        file_id=$fopen("sim/build/audio_record_top_expected.txt","w");
        for(j=0;j<count;j=j+1)$fdisplay(file_id,"%0d",$signed(expected[j]));$fclose(file_id);
        $display("PASS top live recording: %0d samples bit-exact with external I2S; physical HC05/2Mbps UART, touch/IR/classified gesture/guitar/effect/volume, CTS pause, TDM deadlines and HUB75 scan",count);$finish;
    end
    initial begin #80000000;$fatal(1,"Top recorder timeout samples=%0d",count);end
endmodule
