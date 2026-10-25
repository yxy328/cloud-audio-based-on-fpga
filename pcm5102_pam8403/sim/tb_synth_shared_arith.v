`timescale 1ns/1ps
// Directed check of the shared-arithmetic contract. The joint system test can
// never observe a touch grant inside LOOK_AUX2 because the sensor keeps
// requesting there, so this bench drives that window explicitly.
module tb_synth_shared_arith;
    reg clk=0;
    always #10 clk=~clk;
    reg sensor_mul_request=0,touch_mul_request=0;
    reg signed [32:0] sensor_mul_a=0,touch_mul_a=0;
    reg signed [17:0] sensor_mul_b=0,touch_mul_b=0;
    reg sensor_sine_request=0,touch_sine_request=0;
    reg [31:0] sensor_sine_phase=0,touch_sine_phase=0;
    wire touch_mul_grant,touch_sine_grant;
    wire signed [50:0] product;
    wire signed [15:0] sine;
    // The ROM output must follow the arbitrated phase input, one edge later.
    wire signed [15:0] reference_sine;
    touch_sine_rom u_reference(.clk(clk),
        .phase(sensor_sine_request ? sensor_sine_phase : touch_sine_phase),.sample(reference_sine));

    synth_shared_arith dut(
        .clk(clk),
        .sensor_mul_request(sensor_mul_request),.touch_mul_request(touch_mul_request),
        .sensor_mul_a(sensor_mul_a),.touch_mul_a(touch_mul_a),
        .sensor_mul_b(sensor_mul_b),.touch_mul_b(touch_mul_b),
        .touch_mul_grant(touch_mul_grant),.product(product),
        .sensor_sine_request(sensor_sine_request),.touch_sine_request(touch_sine_request),
        .sensor_sine_phase(sensor_sine_phase),.touch_sine_phase(touch_sine_phase),
        .touch_sine_grant(touch_sine_grant),.sine(sine));

    integer errors=0,rom_checks=0,stall_run=0,max_stall=0,rom_stall_run=0,max_rom_stall=0;
    task fail;
        input [255:0] text;
        begin errors=errors+1;$display("FAIL %0s (t=%0t)",text,$time); end
    endtask
    task check_grant;
        input expected;
        input [255:0] text;
        begin if(touch_mul_grant!==expected) begin
            errors=errors+1;$display("FAIL %0s grant=%b expected=%b",text,touch_mul_grant,expected);end
        end
    endtask
    task check_product;
        input signed [50:0] expected;
        input [255:0] text;
        begin if(product!==expected) begin
            errors=errors+1;$display("FAIL %0s product=%0d expected=%0d",text,product,expected);end
        end
    endtask
    task check_rom_grant;
        input expected;
        input [255:0] text;
        begin if(touch_sine_grant!==expected) begin
            errors=errors+1;$display("FAIL %0s rom_grant=%b expected=%b",text,touch_sine_grant,expected);end
        end
    endtask
    integer k;
    always @(posedge clk)begin
        if(sine!==reference_sine)begin
            errors=errors+1;$display("FAIL rom output %0d expects %0d",sine,reference_sine);
        end else rom_checks=rom_checks+1;
        if(touch_mul_request && !touch_mul_grant)stall_run=stall_run+1;else stall_run=0;
        if(stall_run>max_stall)max_stall=stall_run;
        if(stall_run>6)begin errors=errors+1;$display("FAIL wait bound %0d",stall_run);end
        if(touch_sine_request && !touch_sine_grant)rom_stall_run=rom_stall_run+1;else rom_stall_run=0;
        if(rom_stall_run>max_rom_stall)max_rom_stall=rom_stall_run;
        if(rom_stall_run>6)begin errors=errors+1;$display("FAIL rom wait bound %0d",rom_stall_run);end
    end
    initial begin
        repeat(2)@(negedge clk);
        check_grant(0,"idle");
        check_product(0,"idle product");
        // One sensor multiply, no contender.
        sensor_mul_a=33'sd100;sensor_mul_b=18'sd7;sensor_mul_request=1;
        @(negedge clk);check_grant(0,"sensor only");check_product(51'sd700,"sensor only product");
        // LOOK_AUX window: both clients request. The touch must wait and the
        // sensor product must survive the edge.
        touch_mul_a=33'sd3;touch_mul_b=-18'sd5;touch_mul_request=1;
        @(negedge clk);check_grant(0,"look aux priority");check_product(51'sd700,"look aux product");
        // LOOK_AUX2 window: the sensor requests again purely to keep the result.
        @(negedge clk);check_grant(0,"look aux2 retention");check_product(51'sd700,"look aux2 product");
        // PITCH_MUL: the sensor stops requesting and would consume product here.
        sensor_mul_request=0;
        #1 check_grant(1,"post window grant");check_product(51'sd700,"consume point product");
        @(negedge clk);check_product(-51'sd15,"touch product after grant");
        // Negative operands keep their sign through the shared multiplier.
        touch_mul_request=0;sensor_mul_a=-33'sd3;sensor_mul_b=18'sd5;sensor_mul_request=1;
        @(negedge clk);check_product(-51'sd15,"signed sensor product");
        // Full-width operands must not alias.
        sensor_mul_a=33'sd4294967295;sensor_mul_b=18'sd131071;
        @(negedge clk);check_product(51'sd4294967295*51'sd131071,"wide product");
        sensor_mul_request=0;
        @(negedge clk);
        // ROM arbitration: the sensor owns at most six consecutive edges
        // (IDLE sample_ce plus LOOK_BASE..LOOK_AUX2).
        sensor_sine_phase=32'h0000_0000;touch_sine_phase=32'h1234_5678;
        touch_sine_request=1;sensor_sine_request=1;
        for(k=0;k<6;k=k+1)begin
            #1 check_rom_grant(0,"sensor rom priority");
            @(negedge clk);
        end
        sensor_sine_request=0;
        #1 check_rom_grant(1,"post rom grant");
        @(negedge clk);check_rom_grant(1,"post rom grant held");
        if(sine!==16'sh36ba)begin
            // touch phase 0x12345678 selects table[72]=16'h36ba
            errors=errors+1;$display("FAIL rom data %h",sine);
        end
        touch_sine_request=0;
        @(negedge clk);
        if(max_stall<2)$display("NOTE max observed multiply wait %0d",max_stall);
        if(max_rom_stall!=6)begin errors=errors+1;$display("FAIL rom wait not exercised %0d",max_rom_stall);end
        if(rom_checks<12)begin errors=errors+1;$display("FAIL rom checks %0d",rom_checks);end
        if(errors)begin $display("FAIL shared arithmetic arbitration errors=%0d",errors);$fatal(1);end
        $display("PASS shared arithmetic arbitration: sensor priority, look_aux2 retention, signed and 51-bit products, rom phase mux, wait %0d/%0d, %0d rom comparisons",
            max_stall,max_rom_stall,rom_checks);
        $finish;
    end
endmodule

