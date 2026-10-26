`timescale 1ns/1ps
module tb_adsr_staging_equivalence;
    reg clk=0;always #5 clk=~clk;
    reg resetn=0,request=0,restore=0,profile=0;
    reg [15:0] attack=0,decay=0,sustain=0,release_ms=0;
    wire done,reference_done;
    wire [63:0] touch_config,reference_touch;
    wire [129:0] sensor_config,reference_sensor;
    adsr_config dut(.clk(clk),.resetn(resetn),.request(request),.restore(restore),.profile(profile),
        .attack_ms(attack),.decay_ms(decay),.sustain_percent(sustain),.release_ms(release_ms),
        .done(done),.touch_config(touch_config),.sensor_config(sensor_config));
    adsr_config_staging_reference reference(.clk(clk),.resetn(resetn),.request(request),.restore(restore),.profile(profile),
        .attack_ms(attack),.decay_ms(decay),.sustain_percent(sustain),.release_ms(release_ms),
        .done(reference_done),.touch_config(reference_touch),.sensor_config(reference_sensor));
    integer checks=0,commits=0,resets=0,i,p,target_state,target_field,target_left;
    reg [31:0] random=32'hc7a18495;
    always @(posedge clk)begin
        #1;
        if({done,touch_config,sensor_config}!=={reference_done,reference_touch,reference_sensor})
            $fatal(1,"ADSR staging mismatch state=%0d field=%0d left=%0d cycle=%0d",dut.state,dut.field,dut.left,checks);
        checks=checks+1;
        if(done)commits=commits+1;
    end
    task random_inputs;
        begin
            random=random^(random<<13);random=random^(random>>17);random=random^(random<<5);
            attack=random[15:0];decay=random[31:16];sustain=random[6:0];release_ms=random[23:8];
        end
    endtask
    task start;
        begin @(negedge clk);request=1;@(negedge clk);request=0;end
    endtask
    task complete;
        integer waited;
        begin
            waited=0;
            while(!done && waited<200)begin @(negedge clk);waited=waited+1;end
            if(!done)$fatal(1,"ADSR completion timeout");
            @(negedge clk);
        end
    endtask
    task reset_during_operation;
        begin
            @(negedge clk);resetn=0;request=0;
            @(negedge clk);resetn=1;resets=resets+1;
            random_inputs;profile=!profile;start;complete;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);resetn=1;
        for(p=0;p<2;p=p+1)begin
            profile=p;
            for(i=0;i<=1000;i=i+1)begin
                attack=i;decay=(i*37)%1001;sustain=i%101;release_ms=1000-i;
                start;complete;
            end
            restore=1;start;complete;restore=0;
        end
        for(target_state=1;target_state<=5;target_state=target_state+1)begin
            for(target_field=0;target_field<4;target_field=target_field+1)begin
                // CONVERT has only the three time fields; COMMIT follows field3.
                if((target_state!=5 || target_field<3) && (target_state!=3 || target_field==3))begin
                    random_inputs;start;
                    wait(dut.state==target_state && dut.field==target_field);
                    reset_during_operation;
                end
            end
        end
        for(target_field=0;target_field<4;target_field=target_field+1)
            for(target_left=0;target_left<=24;target_left=target_left+1)begin
                random_inputs;start;
                wait(dut.state==2 && dut.field==target_field && dut.left==target_left);
                reset_during_operation;
            end
        // Requests, restores and input mutations while busy retain the
        // original ignored-request semantics and atomic output commit.
        for(i=0;i<128;i=i+1)begin
            random_inputs;profile=i[0];start;
            repeat(20)begin @(negedge clk);random_inputs;request=random[0];restore=random[1];profile=random[2];end
            @(negedge clk);request=0;restore=0;complete;
        end
        $display("PASS ADSR staging: %0d cycle comparisons, %0d completed updates, %0d interrupted requests; both profiles/all1001ms, every divide position, full16-bit inputs, busy input changes",checks,commits,resets);
        $finish;
    end
    initial begin #10000000;$fatal(1,"ADSR staging overall timeout");end
endmodule
