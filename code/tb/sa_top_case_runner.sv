`timescale 1ns/1ps
`default_nettype none

// Shared 16x16 stimulus and checker used by the mode-specific SA top tests.
module sa_top_case_runner #(
    parameter logic [1:0] MODE              = 2'b00,
    parameter int         VECTOR_COUNT      = 1,
    parameter logic [31:0] RANDOM_SEED      = 32'h1a2b_3c4d,
    parameter logic [31:0] B_RANDOM_SEED    = 32'h5a5a_c3c3,
    parameter             CASE_NAME         = "sa_top_case",
    parameter             FSDB_FILE         = "waves/sa_top_case.fsdb",
    parameter             VCD_FILE          = "build/verilator/waves/sa_top_case.vcd"
);

    localparam int DATA_WIDTH = 32;
    localparam int ARRAY_H    = 16;
    localparam int ARRAY_W    = 16;
    localparam int PE_CKG_NUM = 64;

    logic                              sys_ckg;
    logic [PE_CKG_NUM-1:0]             pe_ckg;
    logic                              tpu_rst_n;
    logic                              cpu_tpu_start_sync;
    logic                              cpu_tpu_en_sync;
    logic [DATA_WIDTH*ARRAY_H-1:0]     dat_in_a;
    logic                              dat_in_vld;
    logic                              dat_in_last;
    logic                              cpu_dat_in_b_lock;
    logic [DATA_WIDTH*ARRAY_W-1:0]     cpu_dat_in_b;
    logic [3:0]                        cpu_dat_in_b_sel;
    logic [3:0]                        cpu_h_size;
    logic [3:0]                        cpu_w_size;
    logic [1:0]                        cpu_cpt_mode;
    logic [31:0]                       rpt_active_size;
    logic [DATA_WIDTH*ARRAY_W-1:0]     dat_out;
    logic                              dat_out_vld;
    logic                              dat_out_last;

    // One independent 32-bit A value for every SA input row.
    logic [31:0]                       a_lane_value [0:ARRAY_H-1];

    // Independent B weight for every PE and one expected result per column.
    logic [31:0]                       b_pe_value     [0:ARRAY_H-1][0:ARRAY_W-1];
    logic [31:0]                       expected_value [0:ARRAY_W-1];

`ifdef VERILATOR_TRACE
    initial begin
        $dumpfile(VCD_FILE);
        $dumpvars(0, dut);
    end
`endif

`ifdef FSDB_TRACE
    string fsdb_file_runtime;

    initial begin
        if (!$value$plusargs("FSDB_FILE=%s", fsdb_file_runtime)) begin
            fsdb_file_runtime = FSDB_FILE;
        end

        $fsdbDumpfile(fsdb_file_runtime);
        $fsdbDumpvars(0, dut, "+all");
    end
`endif

    always #1.25 sys_ckg = ~sys_ckg;
    assign pe_ckg = {PE_CKG_NUM{sys_ckg}};

    sa_top dut (
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
            $error("%s: %s", CASE_NAME, message);
            $fatal(1);
        end
    endtask

    // Fixed-seed xorshift generator: random-looking data with repeatable regressions.
    function automatic logic [31:0] next_random(input logic [31:0] current_value);
        logic [31:0] next_value;

        begin
            next_value = current_value;
            next_value = next_value ^ (next_value << 13);
            next_value = next_value ^ (next_value >> 17);
            next_value = next_value ^ (next_value << 5);
            next_random = next_value;
        end
    endfunction

    // Integer modes consume the complete signed 32-bit word in the current PE.
    // Floating-point modes use small finite values so failures remain readable.
    function automatic logic [31:0] make_a_value(input logic [31:0] random_bits);
        logic [15:0] fp16_value;

        begin
            case (MODE)
                2'b00,
                2'b01: make_a_value = random_bits;
                2'b10: begin
                    case (random_bits[1:0])
                        2'd0: fp16_value = 16'h3c00; // FP16 1.0
                        2'd1: fp16_value = 16'h4000; // FP16 2.0
                        2'd2: fp16_value = 16'h4200; // FP16 3.0
                        default: fp16_value = 16'h4400; // FP16 4.0
                    endcase
                    make_a_value = {random_bits[31:16], fp16_value};
                end
                default: begin
                    case (random_bits[1:0])
                        2'd0: make_a_value = 32'h3f80_0000; // FP32 1.0
                        2'd1: make_a_value = 32'h4000_0000; // FP32 2.0
                        2'd2: make_a_value = 32'h4040_0000; // FP32 3.0
                        default: make_a_value = 32'h4080_0000; // FP32 4.0
                    endcase
                end
            endcase
        end
    endfunction

    // Every PE weight is independently selected from the numeric range 1..4.
    function automatic logic [31:0] make_b_value(input logic [31:0] random_bits);
        begin
            if ((MODE == 2'b00) || (MODE == 2'b01)) begin
                make_b_value = 32'd1 + {30'd0, random_bits[1:0]};
            end else begin
                make_b_value = make_a_value(random_bits);
            end
        end
    endfunction

    // Convert the constrained FP operand set back to its integer value.
    function automatic int unsigned fp_value_to_uint(input logic [31:0] fp_value);
        begin
            if (MODE == 2'b10) begin
                case (fp_value[15:0])
                    16'h3c00: fp_value_to_uint = 1;
                    16'h4000: fp_value_to_uint = 2;
                    16'h4200: fp_value_to_uint = 3;
                    default:  fp_value_to_uint = 4;
                endcase
            end else begin
                case (fp_value)
                    32'h3f80_0000: fp_value_to_uint = 1;
                    32'h4000_0000: fp_value_to_uint = 2;
                    32'h4040_0000: fp_value_to_uint = 3;
                    default:       fp_value_to_uint = 4;
                endcase
            end
        end
    endfunction

    // Exact IEEE-754 encoding for the small positive integer FP sums used here.
    function automatic logic [31:0] small_uint_to_fp32(input int unsigned value);
        int unsigned msb_index;
        logic [7:0] exponent_value;
        logic [31:0] normalized_value;

        begin
            if (value == 0) begin
                small_uint_to_fp32 = 32'd0;
            end else begin
                msb_index = 0;
                for (int bit_index = 0; bit_index < 32; bit_index++) begin
                    if (value[bit_index]) begin
                        msb_index = bit_index;
                    end
                end

                normalized_value = value << (23 - msb_index);
                exponent_value   = 8'd127 + msb_index;
                small_uint_to_fp32 = {
                    1'b0,
                    exponent_value,
                    normalized_value[22:0]
                };
            end
        end
    endfunction

    // Generate the complete stationary-weight matrix before B preload starts.
    task automatic prepare_b_matrix;
        logic [31:0] random_state;
        logic [31:0] first_b_value;
        logic        b_has_variation;

        random_state    = B_RANDOM_SEED;
        first_b_value   = '0;
        b_has_variation = 1'b0;

        for (int row = 0; row < ARRAY_H; row++) begin
            $write("%s: B row %0d =", CASE_NAME, row);

            for (int col = 0; col < ARRAY_W; col++) begin
                random_state         = next_random(random_state);
                b_pe_value[row][col] = make_b_value(random_state);

                if ((row == 0) && (col == 0)) begin
                    first_b_value = b_pe_value[row][col];
                end else if (b_pe_value[row][col] != first_b_value) begin
                    b_has_variation = 1'b1;
                end

                $write(" %08h", b_pe_value[row][col]);
            end

            $display("");
        end

        check(b_has_variation, "all 256 B weights unexpectedly have one value");
    endtask

    // Build one reproducible random A vector and the 16 column reference results.
    task automatic prepare_a_vector(input int vector_index);
        logic [31:0]        random_state;
        logic signed [31:0] int_sum;
        logic signed [63:0] int_product;
        integer             fp_sum;

        random_state = RANDOM_SEED ^ (32'h9e37_79b9 * (vector_index + 1));

        for (int row = 0; row < ARRAY_H; row++) begin
            random_state      = next_random(random_state);
            a_lane_value[row] = make_a_value(random_state);
        end

        for (int col = 0; col < ARRAY_W; col++) begin
            int_sum = '0;
            fp_sum  = 0;

            for (int row = 0; row < ARRAY_H; row++) begin
                if ((MODE == 2'b00) || (MODE == 2'b01)) begin
                    int_product = $signed(a_lane_value[row]) *
                                  $signed(b_pe_value[row][col]);
                    int_sum = int_sum + $signed(int_product[31:0]);
                end else begin
                    fp_sum = fp_sum +
                             fp_value_to_uint(a_lane_value[row]) *
                             fp_value_to_uint(b_pe_value[row][col]);
                end
            end

            if ((MODE == 2'b00) || (MODE == 2'b01)) begin
                expected_value[col] = int_sum;
            end else begin
                expected_value[col] = small_uint_to_fp32(fp_sum);
            end
        end

        $write("%s: A vector %0d =", CASE_NAME, vector_index);
        for (int row = 0; row < ARRAY_H; row++) begin
            $write(" %08h", a_lane_value[row]);
        end

        $write("; expected columns =");
        for (int col = 0; col < ARRAY_W; col++) begin
            $write(" %08h", expected_value[col]);
        end
        $display("");
    endtask

    // The CPU-side B interface is 100 MHz. Each high and low phase therefore
    // lasts four 400 MHz sys_ckg cycles. One transaction loads one complete PE row.
    task automatic load_b_row(input int row_index);
        cpu_dat_in_b = '0;
        for (int col = 0; col < ARRAY_W; col++) begin
            cpu_dat_in_b[col*DATA_WIDTH +: DATA_WIDTH] =
                b_pe_value[row_index][col];
        end

        cpu_dat_in_b_sel  = row_index[3:0];
        cpu_dat_in_b_lock = 1'b1;
        repeat (4) sample_cycle();
        cpu_dat_in_b_lock = 1'b0;
        repeat (4) sample_cycle();
    endtask

    // The external A source supplies the row-skewed staircase expected by SA:
    // beat 0 has lane 0 valid, beat 1 has lanes 0..1 valid, and beat 15 has
    // all 16 lanes valid. Unused 32-bit lanes are explicitly driven to zero.
    task automatic drive_a_vector(input int vector_index);
        prepare_a_vector(vector_index);

        for (int input_beat = 0; input_beat < ARRAY_H; input_beat++) begin
            dat_in_a           = '0;
            dat_in_vld         = 1'b1;
            dat_in_last        = (input_beat == ARRAY_H-1);
            cpu_tpu_start_sync = (input_beat == 0);

            for (int row = 0; row <= input_beat; row++) begin
                dat_in_a[row*DATA_WIDTH +: DATA_WIDTH] = a_lane_value[row];
            end

            sample_cycle();
        end

        cpu_tpu_start_sync = 1'b0;
        dat_in_a           = '0;
        dat_in_vld         = 1'b0;
        dat_in_last        = 1'b0;
    endtask

    // Collector beat k is aligned with the final result from bottom-row PE[15][k].
    task automatic collect_and_check;
        int output_beat;
        int timeout_cycle;

        output_beat  = 0;
        timeout_cycle = 0;

        while ((output_beat < ARRAY_W) && (timeout_cycle < 128)) begin
            if (dat_out_vld) begin
                check((^dat_out !== 1'bx),
                      $sformatf("X/Z detected on output beat %0d", output_beat));

                for (int col = 0; col < ARRAY_W; col++) begin
                    if (col <= output_beat) begin
                        check(dat_out[col*DATA_WIDTH +: DATA_WIDTH] ===
                              expected_value[col],
                              $sformatf("output beat %0d, completed column %0d expected %h, got %h",
                                        output_beat,
                                        col,
                                        expected_value[col],
                                        dat_out[col*DATA_WIDTH +: DATA_WIDTH]));
                    end else begin
                        check(dat_out[col*DATA_WIDTH +: DATA_WIDTH] === '0,
                              $sformatf("output beat %0d, unfinished column %0d must be zero, got %h",
                                        output_beat,
                                        col,
                                        dat_out[col*DATA_WIDTH +: DATA_WIDTH]));
                    end
                end

                check(dat_out_last == (output_beat == ARRAY_W-1),
                      $sformatf("dat_out_last is wrong on output beat %0d", output_beat));
                output_beat++;
            end

            if (output_beat < ARRAY_W) begin
                sample_cycle();
                timeout_cycle++;
            end
        end

        check(output_beat == ARRAY_W, "timed out before receiving 16 output beats");
        sample_cycle();
    endtask

    initial begin
        sys_ckg            = 1'b0;
        tpu_rst_n          = 1'b0;
        cpu_tpu_start_sync = 1'b0;
        cpu_tpu_en_sync    = 1'b0;
        dat_in_a           = '0;
        dat_in_vld         = 1'b0;
        dat_in_last        = 1'b0;
        cpu_dat_in_b_lock  = 1'b0;
        cpu_dat_in_b       = '0;
        cpu_dat_in_b_sel   = '0;
        cpu_h_size         = 4'd15;
        cpu_w_size         = 4'd15;
        cpu_cpt_mode       = MODE;

        repeat (2) sample_cycle();
        tpu_rst_n = 1'b1;
        sample_cycle();

        // Enable all 256 PEs before the first B preload and keep them enabled.
        cpu_tpu_en_sync = 1'b1;
        sample_cycle();
        check(rpt_active_size == {16'd16, 16'd16},
              "rpt_active_size must report 16x16");
        check(dut.u_sa_ctrl.pe_en == {ARRAY_H*ARRAY_W{1'b1}},
              "all 256 PE enables must be high");

        prepare_b_matrix();
        for (int row = 0; row < ARRAY_H; row++) begin
            load_b_row(row);
        end

        for (int vector_index = 0; vector_index < VECTOR_COUNT; vector_index++) begin
            drive_a_vector(vector_index);
            collect_and_check();
        end

        $display("%s: PASS", CASE_NAME);
        $finish;
    end

endmodule

`default_nettype wire
