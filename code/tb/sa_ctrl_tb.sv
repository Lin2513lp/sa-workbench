`timescale 1ns/1ps
`default_nettype none

module sa_ctrl_tb;

`ifdef VERILATOR_TRACE
    initial begin
        $dumpfile("build/verilator/waves/sa_ctrl_tb.vcd");
        $dumpvars(0, sa_ctrl_tb);
    end
`endif

`ifdef FSDB_TRACE
    initial begin
        $fsdbDumpfile("waves/sa_ctrl_tb.fsdb");
        $fsdbDumpvars(0, sa_ctrl_tb, "+all");
    end
`endif

    localparam int DATA_WIDTH = 32;
    localparam int ARRAY_H    = 16;
    localparam int ARRAY_W    = 16;
    localparam int PE_CKG_NUM = 64;

    logic sys_ckg;
    logic [PE_CKG_NUM-1:0] pe_ckg;
    logic tpu_rst_n;
    logic cpu_tpu_en_sync;
    logic [DATA_WIDTH*ARRAY_H-1:0] dat_in_a;
    logic dat_in_vld;
    logic dat_in_last;
    logic cpu_dat_in_b_lock;
    logic [DATA_WIDTH*ARRAY_W-1:0] cpu_dat_in_b;
    logic [3:0] cpu_dat_in_b_sel;
    logic [3:0] cpu_h_size;
    logic [3:0] cpu_w_size;
    logic [1:0] cpu_cpt_mode;

    logic [31:0] rpt_active_size;
    logic pe_tpu_rst_n;
    logic [PE_CKG_NUM-1:0] pe_ckg_out;
    logic [1:0] pe_cpt_mode;
    logic [DATA_WIDTH*ARRAY_H-1:0] pe_dat_in_a;
    logic pe_dat_in_vld;
    logic [DATA_WIDTH*ARRAY_W-1:0] pe_dat_in_b;
    logic [ARRAY_H-1:0] pe_b_lock_row;
    logic [ARRAY_H*ARRAY_W-1:0] pe_en;
    logic [3:0] active_w_size;
    logic task_input_last;

    int enabled_count;

    always #1.25 sys_ckg = ~sys_ckg;
    always_comb pe_ckg = {PE_CKG_NUM{sys_ckg}};

    sa_ctrl dut (
        .sys_ckg,
        .pe_ckg,
        .tpu_rst_n,
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
        .pe_tpu_rst_n,
        .pe_ckg_out,
        .pe_cpt_mode,
        .pe_dat_in_a,
        .pe_dat_in_vld,
        .pe_dat_in_b,
        .pe_b_lock_row,
        .pe_en,
        .active_w_size,
        .task_input_last
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
        cpu_tpu_en_sync    = 1'b0;
        dat_in_a           = '0;
        dat_in_vld         = 1'b0;
        dat_in_last        = 1'b0;
        cpu_dat_in_b_lock  = 1'b0;
        cpu_dat_in_b       = '0;
        cpu_dat_in_b_sel   = '0;
        cpu_h_size         = 4'd3; // actual H = 4
        cpu_w_size         = 4'd3; // actual W = 4; all tests use H=W.
        cpu_cpt_mode       = 2'b11;

        repeat (2) sample_cycle();
        tpu_rst_n = 1'b1;
        sample_cycle();

        // A B-load request before enable is a protocol violation and must not
        // update the sampled bus or generate a PE row-write pulse.
        cpu_dat_in_b_lock = 1'b1;
        cpu_dat_in_b_sel  = 4'd1;
        cpu_dat_in_b      = {ARRAY_W{32'hdead_beef}};
        repeat (4) begin
            sample_cycle();
            check(pe_b_lock_row == '0,
                  "B row write must stay low while cpu_tpu_en_sync is low");
        end
        check(pe_dat_in_b == '0,
              "B data must not be sampled before cpu_tpu_en_sync is high");

        // Raising enable while the same lock remains high must not replay the
        // rejected request; a fresh synchronized lock rising edge is required.
        cpu_tpu_en_sync = 1'b1;
        repeat (2) begin
            sample_cycle();
            check(pe_b_lock_row == '0,
                  "rejected B request must not be replayed when enable rises");
        end
        check(pe_dat_in_b == '0,
              "rejected B data must remain discarded after enable rises");

        cpu_dat_in_b_lock = 1'b0;
        repeat (3) sample_cycle();

        // Enable must be high before B preload so the PE weight registers are
        // not held in their pe_en=0 clear state.
        sample_cycle();

        // The 100 MHz source holds the bundled buses for four sys_ckg cycles.
        // Only lock is synchronized; its rising edge samples data and select.
        cpu_dat_in_b_lock = 1'b1;
        cpu_dat_in_b_sel  = 4'd2;
        cpu_dat_in_b      = {ARRAY_W{32'h1234_5678}};
        repeat (3) sample_cycle();

        check(pe_b_lock_row == 16'h0004, "B row 2 must receive one synchronized write pulse");
        check(pe_dat_in_b == {ARRAY_W{32'h1234_5678}}, "event-sampled B data mismatch");

        // On the following PE edge the asserted row pulse writes the already
        // stable sampled bus; it then returns low for the next transfer.
        sample_cycle();
        check(pe_b_lock_row == '0, "B row write enable must be a one-cycle pulse");

        // Changing the asynchronous buses alone must not alter the sampled PE
        // bus. A new value is accepted only after another synchronized rise.
        cpu_dat_in_b_lock = 1'b0;
        cpu_dat_in_b_sel  = 4'd5;
        cpu_dat_in_b      = {ARRAY_W{32'h89ab_cdef}};
        repeat (3) sample_cycle();
        check(pe_dat_in_b == {ARRAY_W{32'h1234_5678}},
              "B bus must hold its previous sample without a new lock rise");

        cpu_dat_in_b_lock = 1'b1;
        repeat (3) sample_cycle();
        check(pe_b_lock_row == 16'h0020, "second lock rise must select B row 5");
        check(pe_dat_in_b == {ARRAY_W{32'h89ab_cdef}},
              "second lock rise must update the sampled B bus");
        sample_cycle();
        check(pe_b_lock_row == '0, "second B row write must also be one cycle");

        enabled_count = 0;
        for (int index = 0; index < ARRAY_H*ARRAY_W; index++) begin
            enabled_count += pe_en[index];
        end
        check(enabled_count == 16, "H=W=4 must enable exactly 16 PEs during preload");

        cpu_dat_in_b_lock = 1'b0;
        sample_cycle();

        check(rpt_active_size == {16'd4, 16'd4}, "rpt_active_size must report actual H/W");
        check(active_w_size == 4'd3,
              "active W size must directly reflect the static input");
        check(pe_cpt_mode == 2'b11, "compute mode must directly reflect the static input");

        cpu_cpt_mode = 2'b01;
        cpu_h_size   = 4'd1;
        cpu_w_size   = 4'd1;
        #0.1;
        check(pe_cpt_mode == 2'b01 && active_w_size == 4'd1,
              "static W/mode must not wait for a start lock");
        check(rpt_active_size == {16'd2, 16'd2},
              "active-size report must directly follow static H/W");

        // last without valid is ignored.
        dat_in_last = 1'b1;
        sample_cycle();
        check(!task_input_last, "dat_in_last must be qualified by dat_in_vld");

        dat_in_vld = 1'b1;
        sample_cycle();
        check(task_input_last, "valid dat_in_last must generate the internal last pulse");

        dat_in_vld      = 1'b0;
        dat_in_last     = 1'b0;
        cpu_tpu_en_sync = 1'b0;
        sample_cycle();
        check(pe_en == '0, "PE enables must clear when cpu_tpu_en_sync falls");

        $display("sa_ctrl_tb: PASS");
        $finish;
    end

endmodule

`default_nettype wire
