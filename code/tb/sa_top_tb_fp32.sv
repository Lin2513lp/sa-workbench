`timescale 1ns/1ps
`default_nettype none

module sa_top_tb_fp32;

    // All 256 PEs use independent FP32 A and B values from 1.0 to 4.0.
    sa_top_case_runner #(
        .MODE            (2'b11),
        .RANDOM_SEED     (32'hf032_0001),
        .B_RANDOM_SEED   (32'hb032_0001),
        .CASE_NAME       ("sa_top_tb_fp32"),
        .FSDB_FILE       ("waves/sa_top_tb_fp32.fsdb"),
        .VCD_FILE        ("build/verilator/waves/sa_top_tb_fp32.vcd")
    ) u_case ();

endmodule

`default_nettype wire
