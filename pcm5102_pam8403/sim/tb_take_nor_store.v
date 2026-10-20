`timescale 1ns/1ps
module tb_take_nor_store;
    reg clk=0;always #10 clk=~clk;
    reg resetn=0,save=0,delete_take=0,take_full=1;
    reg [6:0] count=48;reg [23:0] duration=12345;
    wire busy,boot_done,valid,done,ok,loaded_full;wire [3:0] error;
    wire [6:0] loaded_count;wire [23:0] loaded_duration;
    wire ram_we;wire [5:0] ram_address;wire [47:0] ram_data;reg [47:0] ram_q;
    wire cs_n,sck,mosi,miso;
    reg [47:0] memory[0:63];reg [47:0] reference[0:63];
    take_nor_store #(.DEPTH(64)) dut(.*);
    take_nor_model flash(.*);
    always @(posedge clk)begin
        ram_q<=memory[ram_address];
        if(ram_we)memory[ram_address]<=ram_data;
    end
    integer checks=0,i,erases_before,wren_before;
    task check;input condition;input [255:0] message;begin
        checks=checks+1;if(!condition)$fatal(1,"%0s err=%0d state=%0d",message,error,dut.state);
    end endtask
    task reboot;begin
        @(negedge clk);resetn=0;repeat(8)@(negedge clk);resetn=1;
        wait(boot_done);@(negedge clk);
    end endtask
    task store;input deleting;begin
        @(negedge clk);save=!deleting;delete_take=deleting;
        @(negedge clk);save=0;delete_take=0;
        wait(done);@(negedge clk);
    end endtask
    initial begin
        for(i=0;i<64;i=i+1)begin
            reference[i]=48'hfedcba987654 ^ (48'h10203040506*i);
            memory[i]=reference[i];
        end
        reboot;check(!valid && error==0 && flash.wren_count==0,"blank scan is read-only");
        store(0);check(ok && valid && loaded_count==48,"save with readback");
        check(flash.polls>flash.erases+flash.programs,"poll delayed WIP until completion");
        $writememh("sim/build/take_nor_slot.hex",flash.bytes);
        check(flash.bytes[15]==0 && flash.bytes[8192+15]==8'hff,"commit byte last, old slot untouched");
        for(i=0;i<64;i=i+1)memory[i]=0;
        reboot;check(valid && loaded_count==48 && loaded_duration==12345 && loaded_full,"NOR restart metadata/full flag");
        for(i=0;i<48;i=i+1)check(memory[i]==reference[i],"NOR restart word-for-word");
        // Power loss during body programming of the inactive slot. Old slot
        // must remain replayable, while the unrecognized partial slot locks.
        for(i=0;i<48;i=i+1)memory[i]=~reference[i];
        @(negedge clk);save=1;@(negedge clk);save=0;
        wait(dut.state==15 && dut.operation==1);repeat(800)@(negedge clk);
        reboot;check(valid && loaded_count==48,"interrupted replacement keeps old take");
        for(i=0;i<48;i=i+1)check(memory[i]==reference[i],"interrupted replacement old body");
        wren_before=flash.wren_count;store(0);
        check(!ok && error==8 && flash.wren_count==wren_before,"partial unknown slot write-locked");
        // Simulate explicit offline reprovisioning of only the inactive slot;
        // this is a test fixture, not a recovery operation provided by RTL.
        for(i=8192;i<16384;i=i+1)flash.bytes[i]=8'hff;
        reboot;store(1);check(ok && !valid,"persistent deletion commit");
        reboot;check(!valid && loaded_count==0,"tombstone prevents old take resurrection");
        // A valid header does not claim unrelated padding within its sector.
        flash.bytes[(dut.active_slot ? 8192 : 0)+200]=8'h5a;
        wren_before=flash.wren_count;reboot;
        check(!valid,"foreign padding cannot resurrect a deleted take");
        store(0);check(ok && valid,"save to other owned slot preserves foreign padding");
        wren_before=flash.wren_count;store(0);
        check(!ok && error==8 && flash.wren_count==wren_before,"foreign padding is never erased");
        // Make a fresh test fixture; the DUT never erases this foreign data.
        for(i=0;i<16384;i=i+1)flash.bytes[i]=8'hff;
        reboot;flash.write_protect=1;erases_before=flash.erases;store(0);
        check(!ok && error==9 && flash.erases==erases_before,"write protection fails without erase");
        flash.write_protect=0;flash.drop_program=1;store(0);
        check(!ok && error==10 && flash.bytes[15]==8'hff,"failed body readback never commits");
        flash.drop_program=0;reboot;
        @(negedge clk);save=1;@(negedge clk);save=0;
        wait(dut.state==16);flash.stuck_busy=1;
        wait(dut.state==17);repeat(500)@(negedge clk);
        force dut.watchdog=100000000;@(negedge clk);release dut.watchdog;
        wait(done);@(negedge clk);
        check(!ok && error==9 && cs_n,"stuck WIP watchdog aborts SPI safely");
        flash.stuck_busy=0;
        // Corrupt foreign data in both slots: never issue WREN.
        for(i=0;i<16384;i=i+1)flash.bytes[i]=8'hff;
        flash.bytes[700]=8'h12;flash.bytes[9000]=8'h34;
        wren_before=flash.wren_count;reboot;
        check(!valid && error==8 && flash.wren_count==wren_before,"foreign data lock on boot");
        store(0);check(!ok && error==8 && flash.wren_count==wren_before,"foreign data never erased");
        flash.jedec=24'hef4016;reboot;
        check(!valid && error==8 && flash.wren_count==wren_before,"wrong device locked");
        $display("PASS tb_take_nor_store: %0d checks; behavioral NOR only",checks);$finish;
    end
    initial begin #500000000;$fatal(1,"NOR timeout state=%0d error=%0d",dut.state,error);end
endmodule
