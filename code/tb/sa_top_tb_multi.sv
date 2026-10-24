`timescale 1ns/1ps
`default_nettype none

module sa_top_tb_multi;

    // Three repetitions of all nine H=W/gap bins without reset or disable.
    sa_top_case_runner #(
        .MODE            (2'b00),
        .VECTOR_COUNT    (3),
        .RANDOM_SEED     (32'h4d55_4c54),
        .B_RANDOM_SEED   (32'hb04d_554c),
        .CASE_NAME       ("sa_top_tb_multi"),
        .FSDB_FILE       ("waves/sa_top_tb_multi.fsdb"),
        .VCD_FILE        ("build/verilator/waves/sa_top_tb_multi.vcd")
    ) u_case ();

endmodule

`default_nettype wire
