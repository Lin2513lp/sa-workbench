`timescale 1ns/1ps
`default_nettype none

module sa_top_tb_smoke;

`ifdef VERILATOR_TRACE
    initial begin
        $dumpfile("build/verilator/waves/sa_top_tb_smoke.vcd");
        $dumpvars(0, sa_top_tb_smoke);
    end
`endif

`ifdef FSDB_TRACE
    string fsdb_file_runtime;

    initial begin
        if (!$value$plusargs("FSDB_FILE=%s", fsdb_file_runtime)) begin
            fsdb_file_runtime = "waves/sa_top_tb_smoke.fsdb";
        end

        $fsdbDumpfile(fsdb_file_runtime);
        $fsdbDumpvars(0, sa_top_tb_smoke, "+all");
    end
`endif

    logic        sys_ckg;
    logic        pe_ckg;
    logic        tpu_rst_n;
    logic        cpu_tpu_start_sync;
    logic        cpu_tpu_en_sync;
    logic [31:0] dat_in_a;
    logic        dat_in_vld;
    logic        dat_in_last;
    logic        cpu_dat_in_b_lock;
    logic [31:0] cpu_dat_in_b;
    logic        cpu_dat_in_b_sel;
    logic        cpu_h_size;
    logic        cpu_w_size;
    logic [1:0]  cpu_cpt_mode;
    logic [31:0] rpt_active_size;
    logic [31:0] dat_out;
    logic        dat_out_vld;
    logic        dat_out_last;
    logic        output_seen;

    always #1.25 sys_ckg = ~sys_ckg;
    assign pe_ckg = sys_ckg;

    sa_top #(
        .ARRAY_H      (1),
        .ARRAY_W      (1),
        .H_SIZE_WIDTH (1),
        .W_SIZE_WIDTH (1),
        .B_SEL_WIDTH  (1),
        .PE_CKG_NUM   (1)
    ) dut (
        .sys_ckg,
        .pe_ckg,
        .tpu_rst_n,
        .cpu_tpu_start_sync,
        .cpu_tpu_en_sync,
        .dat_in_a,
        .dat_in_vld,
        .dat_in_last,
        .cpu_dat_in_b_lock,
        .cpu_dat_in_b,
        .cpu_dat_in_b_sel,
        .cpu_h_size,
        .cpu_w_size,
        .cpu_cpt_mode,
        .rpt_active_size,
        .dat_out,
        .dat_out_vld,
        .dat_out_last
    );

    task automatic sample_cycle;
        @(posedge sys_ckg);
        #0.1;
    endtask

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $error("CHECK FAILED: %s", message);
            $fatal(1);
        end
    endtask

    initial begin
        sys_ckg            = 1'b0;
        tpu_rst_n          = 1'b0;
        cpu_tpu_start_sync = 1'b0;
        cpu_tpu_en_sync    = 1'b0;
        dat_in_a           = 32'b0;
        dat_in_vld         = 1'b0;
        dat_in_last        = 1'b0;
        cpu_dat_in_b_lock  = 1'b0;
        cpu_dat_in_b       = 32'b0;
        cpu_dat_in_b_sel   = 1'b0;
        cpu_h_size         = 1'b0;
        cpu_w_size         = 1'b0;
        cpu_cpt_mode       = 2'b01; // INT8, L=1.
        output_seen        = 1'b0;

        repeat (2) sample_cycle();
        tpu_rst_n = 1'b1;
        sample_cycle();

        // Enable precedes B preload and remains high through output drain.
        cpu_tpu_en_sync = 1'b1;
        sample_cycle();

        // Hold the bundled B write for one 100 MHz source interval.
        cpu_dat_in_b_lock = 1'b1;
        cpu_dat_in_b      = 32'd3;
        repeat (4) sample_cycle();
        cpu_dat_in_b_lock = 1'b0;
        repeat (2) sample_cycle();

        // One-beat task: start, A-T0 and last are accepted together.
        cpu_tpu_start_sync = 1'b1;
        dat_in_a           = 32'd7;
        dat_in_vld         = 1'b1;
        dat_in_last        = 1'b1;
        sample_cycle();
        cpu_tpu_start_sync = 1'b0;
        dat_in_vld         = 1'b0;
        dat_in_last        = 1'b0;
        dat_in_a           = 32'b0;

        for (int wait_cycle = 0;
             (wait_cycle < 6) && !output_seen;
             wait_cycle++) begin
            if (dat_out_vld) begin
                check(dat_out == 32'd21, "1x1 SA result must equal 7*3");
                check(dat_out_last, "single-beat result must carry dat_out_last");
                check(rpt_active_size == {16'd1, 16'd1},
                      "active-size report must expose actual 1x1 dimensions");
                output_seen = 1'b1;
            end else begin
                sample_cycle();
            end
        end

        if (!output_seen) begin
            $fatal(1, "sa_top_tb timed out waiting for output");
        end

        $display("sa_top_tb_smoke: PASS");
        $finish;
    end

endmodule

`default_nettype wire
