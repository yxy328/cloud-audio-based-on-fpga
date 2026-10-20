`timescale 1ns/1ps
// Full audio/I2S/SPI paths. UART is accelerated to 500kbps ONLY in simulation;
// the standalone production wrapper remains fixed at 9600bps.
module tb_top_unified;
    reg clk=0;always #10 clk=~clk;
    reg rx=1;reg [7:0] pads=0,ir=0;
    wire tx,bck,lrck,din,hck,lat,oe,flash_cs_n,flash_sck,flash_mosi,flash_miso;
    tri1 scl,sda;
    top #(.ENABLE_FLASH_AUDIO(1),.ENABLE_EVENT_TAKE(1),.EVENT_KEYS_ENABLE(0),.HC05_BAUD(500000),.TOUCH_STARTUP_US(100),.TOUCH_DEBOUNCE_MS(1),
        .ADSR_ATTACK_SAMPLES(4),.ADSR_DECAY_SAMPLES(4),.TOUCH_ADSR_RELEASE_SAMPLES(16),
        .FSR_ENABLE(0),.IR_FILTER_CYCLES(100),.GUITAR_STRING_LENGTH(16)) dut(
        .clk(clk),.key_s1(1'b0),.key_s2(1'b0),.touch_out(pads),.touch_sdo(1'b1),.ir_beam(ir),
        .hc05_rx(rx),.hc05_tx(tx),.audio_rec_cts_n(1'b1),.i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),
        .scl(scl),.sda(sda),.hub_CK(hck),.hub_ST(lat),.hub_OE(oe),
        .flash_cs_n(flash_cs_n),.flash_sck(flash_sck),.flash_mosi(flash_mosi),.flash_miso(flash_miso));
    audio_nor_model #(.END_ADDR(24'h800000)) flash(.cs_n(flash_cs_n),.sck(flash_sck),.mosi(flash_mosi),.miso(flash_miso));
    i2s_pcm_monitor #(.PCM_MIN(-32768),.PCM_MAX(32767),.CAPTURE_FILE("sim/build/unified_i2s.csv")) monitor(
        .bck(bck),.lrck(lrck),.din(din));
    reg [15:0] expected[0:4095];integer i2s_index[0:4095];
    integer count=0,frames=0,nonzero=0,columns=0,latches=0,live_download=0;
    reg binary_mode=0;
    always @(posedge hck)if(dut.resetn)columns=columns+1;
    always @(posedge lat)if(dut.resetn)begin
        if(columns!=64 || oe!==1)$fatal(1,"HUB75 scan deadline");columns=0;latches=latches+1;
    end
    always @(posedge clk)if(dut.resetn && dut.frame_ce)begin
        frames=frames+1;if(dut.u_touch_synth.overrun || dut.sensor_overrun)$fatal(1,"Audio TDM deadline");
        if(dut.flash_pcm.u_audio_take.capturing)begin
            expected[count]=dut.audio_sample;i2s_index[count]=monitor.pcm_count;count=count+1;
            if(dut.audio_sample!=0)nonzero=nonzero+1;
        end
        if(binary_mode && dut.audio_sample!=0)live_download=live_download+1;
    end
    integer replies=0,b,received=0,packet_base=0,packets=0,packet_size;
    reg [255:0] incoming=0,last_reply=0;reg [7:0] data;
    reg [7:0] bytes[0:16383];
    initial forever begin
        @(negedge tx);repeat(50)@(posedge clk);
        for(b=0;b<8;b=b+1)begin repeat(100)@(posedge clk);data[b]=tx;end
        repeat(100)@(posedge clk);if(tx!==1)$fatal(1,"HC05 UART stop bit");
        if(binary_mode)begin
            bytes[received]=data;received=received+1;
            if(received-packet_base>=18)begin
                packet_size={bytes[packet_base+7],bytes[packet_base+6]};
                if(received-packet_base==18+packet_size)begin packets=packets+1;packet_base=received;end
            end
        end else begin
            incoming={incoming[247:0],data};
            if(data==10)begin last_reply=incoming;incoming=0;replies=replies+1;end
        end
    end
    task uart_line;
        input [255:0] message;input integer length;integer c,k;
        begin for(c=length-1;c>=0;c=c-1)begin
            @(negedge clk);rx=0;repeat(100)@(negedge clk);
            for(k=0;k<8;k=k+1)begin rx=message[c*8+k];repeat(100)@(negedge clk);end
            rx=1;repeat(100)@(negedge clk);
        end end
    endtask
    task command;
        input [255:0] message;input integer length;integer target;
        begin target=replies+1;uart_line(message,length);wait(replies==target);
            if(last_reply!=={"OK",8'd13,8'd10})$fatal(1,"Command %0s got %0s",message,last_reply);
        end
    endtask
    task wait_frames;input integer n;integer target;begin target=frames+n;wait(frames>=target);@(negedge clk);end endtask
    task query_status;
        integer target;
        begin target=replies+1;uart_line("AREC?\n",6);wait(replies==target);
            if(last_reply[239:64]!=="AREC,0,0,0,1,2,0,0001,")$fatal(1,"Extended Flash status: %0s",last_reply);
        end
    endtask
    task expect_line;
        input [255:0] message;input integer length;input [255:0] expected_reply;integer target;
        begin target=replies+1;uart_line(message,length);wait(replies==target);
            if(last_reply!==expected_reply)$fatal(1,"Unified command %0s got %0s expected %0s",message,last_reply,expected_reply);
        end
    endtask
    function [7:0] hex_char;input [3:0] n;begin hex_char=n<10 ? "0"+n : "A"+n-10;end endfunction
    function [95:0] hex_word;input [47:0] word;integer n;begin for(n=0;n<12;n=n+1)hex_word[n*8 +: 8]=hex_char(word[n*4 +: 4]);end endfunction
    always @(posedge clk)if(dut.resetn && dut.pcm_resetn && dut.nv_store_busy && dut.audio_rec_busy)
        $fatal(1,"Both stores owned Flash at once");
    integer event_count,event_file;
    reg [255:0] read_command;
    function [15:0] u16;input integer p;begin u16={bytes[p+1],bytes[p]};end endfunction
    function [31:0] u32;input integer p;begin u32={bytes[p+3],bytes[p+2],bytes[p+1],bytes[p]};end endfunction
    function [15:0] crc16;
        input integer p,size;integer a,k;reg [15:0] c;
        begin c=65535;for(a=0;a<size;a=a+1)begin c=c^{bytes[p+a],8'd0};for(k=0;k<8;k=k+1)c=c[15]?(c<<1)^16'h1021:c<<1;end crc16=c;end
    endfunction
    integer off,size,seq,seen,j,kind,file_id,panel_before;
    initial begin
        wait(dut.touch_ready);wait(!dut.audio_rec_busy);wait_frames(3);
        expect_line("PING\n",5,{"PONG",8'd13,8'd10});
        command("VIS,3\n",6);command("VOLUME,16\n",10);
        command("TAKE_REC\n",9);pads=3;wait(dut.touch_keys==3);wait_frames(100);
        pads=1;wait_frames(60);pads=0;wait_frames(60);
        command("TAKE_STOP\n",10);wait(!dut.perf_recording);wait_frames(2);
        if(!dut.perf_available || dut.perf_count<37)$fatal(1,"Unified event recording unavailable");
        event_count=dut.perf_count;
        begin: reset_host_cursor
            integer target;target=replies+1;uart_line("TAKE?\n",6);wait(replies==target);
        end
        command("TAKE_PLAY\n",10);wait(dut.perf_playing);wait(!dut.perf_playing);wait_frames(10);
        command("TAKE_SAVE\n",10);
        expect_line("AREC_PREP\n",10,{"ERR,BUSY",8'd13,8'd10});
        wait(!dut.nv_busy);repeat(3)@(negedge clk);if(!dut.perf_saved || dut.perf_error!=0)$fatal(1,"Unified event Flash save state=%0d error=%0d nv=%0d",dut.take_enabled.u_take.state,dut.perf_error,dut.nv_error);
        expect_line("PING\n",5,{"PONG",8'd13,8'd10});
        // Unit safety test exercises full read-only ownership scan and erase.
        // This fixture starts with an already erased slot to keep top simulation bounded.
        @(negedge clk);dut.flash_pcm.u_audio_take.prepared=1;
        command("AREC_START,0\n",13);
        expect_line("TAKE_REC\n",9,{"ERR,BUSY",8'd13,8'd10});
        expect_line("PING\n",5,{"PONG",8'd13,8'd10});
        pads=7;wait(dut.touch_keys==7);wait_frames(100);ir=3;wait_frames(100);
        force dut.u_gesture.init_done=1;force dut.u_gesture.dir_evaluated=1;
        force dut.u_gesture.start_dir=3'd1;force dut.u_gesture.end_dir=3'd2;
        @(negedge clk);force dut.u_gesture.gesture_valid=1;
        @(negedge clk);force dut.u_gesture.gesture_valid=0;wait_frames(40);
        if(dut.sensor_voice_count<3)$fatal(1,"Sensor mix missing");
        command("GUITAR\n",7);wait_frames(80);command("EFFECT,2,8\n",11);command("VOLUME,8\n",9);
        pads=0;ir=0;wait_frames(60);command("AREC_STOP\n",10);wait(!dut.audio_rec_busy);wait_frames(3);
        if(!dut.audio_rec_valid || dut.audio_rec_error!=0 || count<350 || nonzero<150 || dut.audio_rec_stored_samples!=count)
            $fatal(1,"Recording invalid: count=%0d nonzero=%0d error=%0d",count,nonzero,dut.audio_rec_error);
        query_status();
        pads=7;ir=3;wait_frames(80);panel_before=latches;
        command("AREC_SEND,4660\n",15);binary_mode=1;uart_line("AREC_ACK,65535\n",15);
        // Unrelated commands during download must not inject ASCII responses.
        uart_line("VIZ?\n",5);
        uart_line("AREC_ACK,x\n",11);
        off=0;seq=0;seen=0;kind=0;
        while(kind!=3)begin
            wait(packets>seq);size=u16(off+6);kind=bytes[off+4];
            if({bytes[off],bytes[off+1],bytes[off+2],bytes[off+3]}!=="FAR1" ||
                u16(off+8)!=seq || u16(off+10)!=4660 || u32(off+12)!=seen ||
                crc16(off,16+size)!==u16(off+16+size))$fatal(1,"FAR1 framing/integrity");
            if(seq==0)begin if(kind!=1||size!=12||u32(off+24)!=count)$fatal(1,"START total length");end
            else if(kind==2)for(j=0;j<size/2;j=j+1)begin
                if(u16(off+16+j*2)!==expected[seen])$fatal(1,"Flash/HC05 sample mismatch %0d",seen);
                if(monitor.pcm[i2s_index[seen]]!==$signed(expected[seen]))$fatal(1,"External I2S mismatch %0d",seen);
                seen=seen+1;
            end
            if(seq>9)$fatal(1,"ACK fixture bounds");
            uart_line({"AREC_ACK,",8'd48+seq[7:0],8'd10},11);
            off=off+18+size;seq=seq+1;
        end
        wait(!dut.audio_rec_busy);if(seen!=count||live_download<500||latches-panel_before<64)$fatal(1,"Upload blocked live audio/panel");
        file_id=$fopen("sim/build/audio_unified_top.bin","wb");for(j=0;j<received;j=j+1)$fwrite(file_id,"%c",bytes[j]);$fclose(file_id);
        file_id=$fopen("sim/build/audio_unified_top_expected.txt","w");for(j=0;j<count;j=j+1)$fdisplay(file_id,"%0d",$signed(expected[j]));$fclose(file_id);
        $display("PASS unified top: event capture/replay/Flash commit, busy refusal then PING, PCM %0d samples bit-exact with external I2S and HC05; %0d packets, %0d live download frames; TDM and HUB75 continue",count,seq,live_download);$finish;
    end
    initial begin #350000000;$fatal(1,"top Flash timeout state=%0d count=%0d packets=%0d received=%0d",dut.flash_pcm.u_audio_take.state,count,packets,received);end
endmodule
