`timescale 1ns/1ps
`default_nettype none

module pe_array_16x16_tb;

`ifdef VERILATOR_TRACE
    initial begin
        $dumpfile("build/verilator/waves/pe_array_16x16_tb.vcd");
        $dumpvars(0, pe_array_16x16_tb);
    end
`endif

`ifdef FSDB_TRACE
    initial begin
        $fsdbDumpfile("waves/pe_array_16x16_tb.fsdb");
        $fsdbDumpvars(0, pe_array_16x16_tb, "+all");
    end
`endif

    localparam int DATA_WIDTH = 32;
    localparam int ARRAY_H    = 2;
    localparam int ARRAY_W    = 2;
    localparam int PE_CKG_NUM = 1;

    logic                              clk;
    logic [PE_CKG_NUM-1:0]             pe_ckg;
    logic                              tpu_rst_n;
    logic [ARRAY_H*ARRAY_W-1:0]        pe_en;
    logic [1:0]                        cpt_mode;
    logic [DATA_WIDTH*ARRAY_H-1:0]     dat_in_a;
    logic                              dat_in_vld;
    logic [DATA_WIDTH*ARRAY_W-1:0]     dat_in_b;
    logic [ARRAY_H-1:0]                b_lock_row;
    logic [DATA_WIDTH*ARRAY_W-1:0]     raw_dat_out;
    logic [ARRAY_W-1:0]                raw_dat_out_vld;

    assign pe_ckg = {PE_CKG_NUM{clk}};
    always #1.25 clk = ~clk;

    pe_array_16x16 #(
        .DATA_WIDTH (DATA_WIDTH),
        .ARRAY_H    (ARRAY_H),
        .ARRAY_W    (ARRAY_W),
        .PE_CKG_NUM (PE_CKG_NUM)
    ) dut (
        .pe_ckg,
        .tpu_rst_n,
        .pe_en,
        .cpt_mode,
        .dat_in_a,
        .dat_in_vld,
        .dat_in_b,
        .b_lock_row,
        .raw_dat_out,
        .raw_dat_out_vld
    );

    task automatic drive_cycle(
        input logic [31:0] lane0,
        input logic [31:0] lane1,
        input logic        valid
    );
        dat_in_a   = {lane1, lane0};
        dat_in_vld = valid;
        @(posedge clk);
        #0.1;
    endtask

    task automatic check_lane(
        input int unsigned lane,
        input logic [31:0] expected_data,
        input logic        expected_valid,
        input string       message
    );
        if ((raw_dat_out[lane*DATA_WIDTH +: DATA_WIDTH] !== expected_data) ||
            (raw_dat_out_vld[lane] !== expected_valid)) begin
            $error("%s: lane=%0d data=%0d valid=%0b expected_data=%0d expected_valid=%0b",
                   message, lane,
                   raw_dat_out[lane*DATA_WIDTH +: DATA_WIDTH],
                   raw_dat_out_vld[lane], expected_data, expected_valid);
            $fatal(1);
        end
    endtask

    initial begin
        clk          = 1'b0;
        tpu_rst_n    = 1'b0;
        pe_en        = '0;
        cpt_mode     = 2'b01; // INT8 uses the one-cycle PE path.
        dat_in_a     = '0;
        dat_in_vld   = 1'b0;
        dat_in_b     = '0;
        b_lock_row   = '0;

        repeat (2) @(posedge clk);
        #0.1;
        tpu_rst_n = 1'b1;
        pe_en     = '1;

        // B = [[2, 3], [5, 7]]. b_lock_row selects one complete PE row.
        dat_in_b   = {32'd3, 32'd2};
        b_lock_row = 2'b01;
        @(posedge clk);
        #0.1;

        dat_in_b   = {32'd7, 32'd5};
        b_lock_row = 2'b10;
        @(posedge clk);
        #0.1;
        b_lock_row = '0;

        // A = [[11, 13], [17, 19]], already skewed at the first-column input.
        drive_cycle(32'd11, 32'd0,  1'b1); // A-T0
        drive_cycle(32'd17, 32'd13, 1'b1); // A-T1
        check_lane(0, 32'd87, 1'b1, "C[0][0] must reach bottom column 0");

        drive_cycle(32'd0, 32'd19, 1'b1);  // A-T2
        check_lane(0, 32'd129, 1'b1, "C[1][0] must reach bottom column 0");
        check_lane(1, 32'd124, 1'b1, "C[0][1] must reach bottom column 1");

        drive_cycle(32'd0, 32'd0, 1'b0);   // Drain the final horizontal A hop.
        check_lane(1, 32'd184, 1'b1, "C[1][1] must reach bottom column 1");

        // Dynamic H=W=1: inactive lower row carries column0 to the bottom;
        // inactive column1 must remain zero/invalid.
        tpu_rst_n  = 1'b0;
        pe_en      = '0;
        dat_in_a   = '0;
        dat_in_vld = 1'b0;
        @(posedge clk);
        #0.1;
        tpu_rst_n = 1'b1;
        pe_en     = 4'b0001;

        dat_in_b   = {32'd3, 32'd2};
        b_lock_row = 2'b01;
        @(posedge clk);
        #0.1;
        b_lock_row = '0;

        drive_cycle(32'd4, 32'd0, 1'b1);
        check_lane(0, 32'd8, 1'b1, "inactive lower row must pass column 0");
        drive_cycle(32'd0, 32'd0, 1'b0);
        check_lane(1, 32'd0, 1'b0, "inactive column1 must stay zero and invalid");

        $display("pe_array_16x16_tb: PASS");
        $finish;
    end

endmodule

`default_nettype wire
