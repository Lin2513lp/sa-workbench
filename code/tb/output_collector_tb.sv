`timescale 1ns/1ps
`default_nettype none

module output_collector_tb;

`ifdef VERILATOR_TRACE
    initial begin
        $dumpfile("build/verilator/waves/output_collector_tb.vcd");
        $dumpvars(0, output_collector_tb);
    end
`endif

`ifdef FSDB_TRACE
    initial begin
        $fsdbDumpfile("waves/output_collector_tb.fsdb");
        $fsdbDumpvars(0, output_collector_tb, "+all");
    end
`endif

    localparam int DATA_WIDTH = 32;
    localparam int ARRAY_W    = 4;

    logic                             sys_ckg;
    logic                             tpu_rst_n;
    logic [1:0]                       active_w_size;
    logic                             task_input_last;
    logic [1:0]                       cpt_mode;
    logic [DATA_WIDTH*ARRAY_W-1:0]    raw_dat_in;
    logic [ARRAY_W-1:0]               raw_dat_in_vld;
    logic [DATA_WIDTH*ARRAY_W-1:0]    dat_out;
    logic                             dat_out_vld;
    logic                             dat_out_last;

    always #1.25 sys_ckg = ~sys_ckg;

    output_collector #(
        .DATA_WIDTH   (DATA_WIDTH),
        .ARRAY_W      (ARRAY_W),
        .W_SIZE_WIDTH (2)
    ) dut (
        .sys_ckg,
        .tpu_rst_n,
        .active_w_size,
        .task_input_last,
        .cpt_mode,
        .raw_dat_in,
        .raw_dat_in_vld,
        .dat_out,
        .dat_out_vld,
        .dat_out_last
    );

    task automatic sample_cycle;
        @(posedge sys_ckg);
        #0.1;
    endtask

    task automatic drive_raw(
        input logic [31:0] col0,
        input logic [31:0] col1,
        input logic [31:0] col2,
        input logic [31:0] col3,
        input logic [3:0]  valid
    );
        raw_dat_in     = {col3, col2, col1, col0};
        raw_dat_in_vld = valid;
        #0.1;
    endtask

    task automatic check(
        input logic condition,
        input string message
    );
        if (!condition) begin
            $error("CHECK FAILED: %s", message);
            $fatal(1);
        end
    endtask

    initial begin
        sys_ckg         = 1'b0;
        tpu_rst_n       = 1'b0;
        active_w_size   = 2'd3; // Actual W=4 output beats.
        task_input_last = 1'b0;
        cpt_mode        = 2'b01; // INT8, L=1.
        raw_dat_in      = '0;
        raw_dat_in_vld  = '0;

        repeat (2) sample_cycle();
        tpu_rst_n = 1'b1;
        sample_cycle();

        // The final valid A beat is PE pipeline cycle 1 for INT8.
        task_input_last = 1'b1;
        sample_cycle();
        task_input_last = 1'b0;

        // Beat 0: only PE[last_row][0] has reached its final result.
        drive_raw(32'd10, 32'd91, 32'd92, 32'd93, 4'b0001);
        check(dat_out_vld, "INT8 output must start at L=1");
        check(dat_out == {32'd0, 32'd0, 32'd0, 32'd10},
              "beat 0 must expose only bottom PE column 0");
        check(!dat_out_last, "beat 0 cannot be last for W=4");

        // Beat 1: only column 1 is newly valid; column 0 must be retained.
        sample_cycle();
        drive_raw(32'd91, 32'd20, 32'd92, 32'd93, 4'b0010);
        check(dat_out == {32'd0, 32'd0, 32'd20, 32'd10},
              "beat 1 must retain column 0 and append column 1");
        check(!dat_out_last, "beat 1 cannot be last for W=4");

        // Beat 2: only column 2 is newly valid; columns 0 and 1 are retained.
        sample_cycle();
        drive_raw(32'd91, 32'd92, 32'd30, 32'd93, 4'b0100);
        check(dat_out == {32'd0, 32'd30, 32'd20, 32'd10},
              "beat 2 must retain columns 0 and 1 and append column 2");
        check(!dat_out_last, "beat 2 cannot be last for W=4");

        // Beat 3: only column 3 is newly valid; the final bus contains all results.
        sample_cycle();
        drive_raw(32'd91, 32'd92, 32'd93, 32'd40, 4'b1000);
        check(dat_out == {32'd40, 32'd30, 32'd20, 32'd10},
              "beat 3 must contain all four accumulated column results");
        check(dat_out_last, "last must accompany the full W=4 snapshot");

        sample_cycle();
        check(!dat_out_vld && !dat_out_last,
              "output window must close after active_w_size+1 beats");

        // FP32 uses L=4. With W=1 it emits exactly one output beat.
        active_w_size   = 2'd0;
        cpt_mode        = 2'b11;
        raw_dat_in      = {32'd103, 32'd102, 32'd101, 32'd55};
        raw_dat_in_vld  = 4'b0001;
        task_input_last = 1'b1;
        sample_cycle();
        task_input_last = 1'b0;

        repeat (2) begin
            check(!dat_out_vld, "FP32 output window opened too early");
            sample_cycle();
        end
        check(!dat_out_vld, "FP32 output window opened before L=4");
        sample_cycle();
        check(dat_out_vld && dat_out_last && dat_out[31:0] == 32'd55,
              "FP32 W=1 result must appear at L=4");
        check(dat_out[127:32] == 96'b0,
              "inactive FP32 lanes must be zero");

        // FP16 uses L=7.
        sample_cycle();
        cpt_mode        = 2'b10;
        raw_dat_in      = {32'd203, 32'd202, 32'd201, 32'd66};
        raw_dat_in_vld  = 4'b0001;
        task_input_last = 1'b1;
        sample_cycle();
        task_input_last = 1'b0;

        repeat (5) begin
            check(!dat_out_vld, "FP16 output window opened too early");
            sample_cycle();
        end
        check(!dat_out_vld, "FP16 output window opened before L=7");
        sample_cycle();
        check(dat_out_vld && dat_out_last && dat_out[31:0] == 32'd66,
              "FP16 W=1 result must appear at L=7");

        $display("output_collector_tb: PASS");
        $finish;
    end

endmodule

`default_nettype wire
