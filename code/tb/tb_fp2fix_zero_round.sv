`timescale 1ns/1ps
// Exhaustive finite FP16 -> INT16 conversion regression. Compile with fp2fix.v.
module tb_fp2fix_zero_round;
    logic clk=0, rst_n=0, en=1, vld_in=0;
    logic [15:0] data_in=0;
    wire signed [15:0] data_out;
    wire overflow, underflow, vld_out;
    integer checked=0, errors=0, expected;
    FP2FIX dut(.*);
    always #1.25 clk=~clk;

    // Independent mathematical nearest integer, ties away from zero,
    // saturating to INT16. Finite subnormals round to integer zero.
    function automatic integer reference(input logic [15:0] value);
        integer e, mantissa, shift, magnitude;
        begin
            e=int'(value[14:10]);
            mantissa=1024+int'(value[9:0]);
            if(e==0) magnitude=0;
            else if(e>=30) magnitude=value[15]?32768:32767;
            else if(e<25) begin
                shift=25-e;
                magnitude=(mantissa+(1<<(shift-1)))>>shift;
            end else magnitude=mantissa<<(e-25);
            reference=value[15]?-magnitude:magnitude;
        end
    endfunction

    initial begin
        for(integer bits=0;bits<65536;bits=bits+1) begin
            if(((bits>>10)&31)!=31) begin
                @(negedge clk);rst_n=0;vld_in=0;
                repeat(2)@(negedge clk);
                data_in=16'(bits);rst_n=1;vld_in=1;
                repeat(7)@(negedge clk);
                expected=reference(data_in);checked=checked+1;
                if(!vld_out || $isunknown(data_out) || $signed(data_out)!=expected) begin
                    errors=errors+1;
                    if(errors<=10)$display("FP2FIX_CHECK_FAIL input=%04h actual=%0d expected=%0d valid=%0d",data_in,$signed(data_out),expected,vld_out);
                end
            end
        end
        if(checked!=63488 || errors!=0)$fatal(1,"FP2FIX regression checked=%0d errors=%0d",checked,errors);
        $display("FP2FIX_ZERO_ROUND_PASS checked=%0d errors=%0d",checked,errors);
        $finish;
    end
    initial begin #10000000;$fatal(1,"FP2FIX regression timeout");end
endmodule
