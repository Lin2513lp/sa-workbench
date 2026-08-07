`timescale 1ns/1ps
`default_nettype none

module sa_top_tb_int4;

    // Random signed 32-bit A words and independent integer B weights from 1 to 4.
    sa_top_case_runner #(
        .MODE            (2'b00),
        .RANDOM_SEED     (32'h1040_0001),
        .B_RANDOM_SEED   (32'hb040_0001),
        .CASE_NAME       ("sa_top_tb_int4"),
        .FSDB_FILE       ("waves/sa_top_tb_int4.fsdb"),
        .VCD_FILE        ("build/verilator/waves/sa_top_tb_int4.vcd")
    ) u_case ();

endmodule

`default_nettype wire
