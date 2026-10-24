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

    logic sa_pipeline_empty;
    logic [31:0] b_pe_value [0:15][0:15];
    logic [31:0] a_matrix [0:63][0:15];
    int a_numeric [0:63][0:15];
    logic [31:0] golden [0:63][0:15];
    int checks=0, matrix_results=0, jobs=0, zero_results=0;
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
        .dat_out_last,
        .sa_pipeline_empty
    );

    task automatic sample_cycle;
        @(posedge sys_ckg);
        #0.1;
    endtask

    task automatic check(input logic condition, input string message);
        checks++;
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


    // Independent arithmetic oracle: original A vectors and stationary B only.
    // FP operands/results are small exactly representable nonnegative integers.
    // Test stimulus independently maps original vector k/lane r to edge pop[k]+r;
    // it does not instantiate CTRL or read collector valid/countdown registers.
    task automatic prepare_matrices(input int n, input int job_id);
        logic [31:0] rng;
        int sum;
        rng = B_RANDOM_SEED ^ (32'h9e3779b9 * (job_id+1));
        for (int r=0; r<16; r++) begin
            for (int c=0; c<16; c++) begin
                rng=next_random(rng);
                b_pe_value[r][c]=make_b_value(rng);
            end
        end
        rng = RANDOM_SEED ^ (32'h85ebca6b * (job_id+1));
        for (int k=0; k<64; k++) begin
            for (int r=0; r<16; r++) begin
                rng=next_random(rng);
                // Include valid zero vectors, including the LAST vector.
                if ((k%4)==0 || k==63) a_numeric[k][r]=0;
                else if (MODE<2) a_numeric[k][r]=int'(rng%13)-6;
                else a_numeric[k][r]=int'(rng%4)+1;
                if (MODE<2) a_matrix[k][r]=32'(a_numeric[k][r]);
                else if (a_numeric[k][r]==0) a_matrix[k][r]=0;
                else if (MODE==3) a_matrix[k][r]=small_uint_to_fp32(a_numeric[k][r]);
                else begin
                    case (a_numeric[k][r])
                        1:a_matrix[k][r]=32'h00003c00;
                        2:a_matrix[k][r]=32'h00004000;
                        3:a_matrix[k][r]=32'h00004200;
                        default:a_matrix[k][r]=32'h00004400;
                    endcase
                end
            end
            for (int c=0; c<n; c++) begin
                sum=0;
                for (int r=0; r<n; r++) begin
                    if (MODE<2) sum += a_numeric[k][r] * int'($signed(b_pe_value[r][c]));
                    else sum += a_numeric[k][r] * fp_value_to_uint(b_pe_value[r][c]);
                end
                golden[k][c]=(MODE<2)?32'(sum):small_uint_to_fp32(sum);
            end
        end
    endtask

    // CPU B write is held for four SYS cycles per high/low phase as before.
    task automatic load_b_row(input int r);
        @(negedge sys_ckg);
        cpu_dat_in_b='0;
        for (int c=0; c<16; c++) cpu_dat_in_b[c*32+:32]=b_pe_value[r][c];
        cpu_dat_in_b_sel=4'(r);
        cpu_dat_in_b_lock=1;
        repeat(4) sample_cycle();
        @(negedge sys_ckg);
        cpu_dat_in_b_lock=0;
        repeat(4) sample_cycle();
    endtask

    task automatic run_stream(input int n, input int count, input int repetition);
        int spacing, last_pop, latency, end_cycle, t, source_t, k;
        int job_results, last_pulses;
        logic [511:0] expected_bus;
        logic expected_valid, expected_last;
        jobs++;
        spacing=1;
        last_pop=(count-1)*spacing;
        latency=(MODE==2)?7:((MODE==3)?4:1);
        // Drain all physical16-lane padding, then test additional quiet edges.
        end_cycle=last_pop+15+2*(n-1)+(latency-1)+6;
        job_results=0; last_pulses=0;
        @(negedge sys_ckg);
        cpu_h_size=4'(n-1); cpu_w_size=4'(n-1);
        cpu_tpu_en_sync=1;
        repeat(3) sample_cycle();
        check(rpt_active_size=={16'(n),16'(n)},"H=W active-size report");
        prepare_matrices(n,jobs+repetition);
        // Reload after N changes; disabled PEs clear their stationary weights.
        for(int r=0;r<16;r++) load_b_row(r);
        for(t=0;t<=end_cycle;t++) begin
            @(negedge sys_ckg);
            dat_in_a='0; dat_in_vld=0;
            dat_in_last=(t==last_pop+15);
            cpu_tpu_start_sync=(t==0);
            for(int r=0;r<16;r++) begin
                source_t=t-r;
                if(source_t>=0 && source_t<=last_pop && source_t%spacing==0) begin
                    k=source_t/spacing;
                    dat_in_a[r*32+:32]=a_matrix[k][r];
                    dat_in_vld=1;
                end
            end
            sample_cycle();
            expected_bus='0; expected_valid=0; expected_last=0;
            for(int c=0;c<n;c++) begin
                source_t=t-15-(n-1)-c-(latency-1);
                if(source_t>=0 && source_t<=last_pop && source_t%spacing==0) begin
                    k=source_t/spacing;
                    expected_bus[c*32+:32]=golden[k][c];
                    expected_valid=1;
                    expected_last |= k==count-1 && c==n-1;

                    job_results++;matrix_results++;
                    if(golden[k][c]==0) zero_results++;
                end
            end
            check(dat_out===expected_bus,
                $sformatf("full512-bit output mode=%0d N=%0d length=%0d T=%0d expected=%h got=%h",MODE,n,count,t,expected_bus,dat_out));
            check(dat_out_vld===expected_valid,"exact output valid including startup/tail");
            check(dat_out_last===expected_last,"exact output LAST including zero result");
            if(dat_out_last) last_pulses++;
            if(t>last_pop+15+2*(n-1)+(latency-1))
                check(sa_pipeline_empty===1'b1,"all padding PE results drained");
        end
        check(job_results==count*n,"all packet vectors x N complete matrix results checked");
        check(last_pulses==1,"exactly one output LAST per task");
        $display("%s: STREAM_PASS mode=%0d H=%0d W=%0d length=%0d results=%0d",CASE_NAME,MODE,n,n,count,job_results);
    endtask

    initial begin
        sys_ckg=0; tpu_rst_n=0;
        cpu_tpu_start_sync=0; cpu_tpu_en_sync=0;
        dat_in_a=0; dat_in_vld=0; dat_in_last=0;
        cpu_dat_in_b_lock=0; cpu_dat_in_b=0; cpu_dat_in_b_sel=0;
        cpu_h_size=15; cpu_w_size=15; cpu_cpt_mode=MODE;
        repeat(2) sample_cycle();
        @(negedge sys_ckg); tpu_rst_n=1;
        // VECTOR_COUNT now counts repetitions of the complete18-bin contiguous-packet suite.
        // Same enable remains high across N1->N4->N16 and subsequent N1 tasks.
        for(int rep=0;rep<VECTOR_COUNT;rep++) begin
            for(int size_bin=0;size_bin<3;size_bin++) begin
                for(int length_bin=0;length_bin<6;length_bin++) begin
                    run_stream((size_bin==0)?1:((size_bin==1)?4:16),
                               (length_bin==0)?1:((length_bin==1)?2:((length_bin==2)?4:((length_bin==3)?16:((length_bin==4)?31:64)))),rep);
                end
            end
        end
        $display("%s: PASS jobs=%0d results=%0d valid_zeros=%0d checks=%0d",CASE_NAME,jobs,matrix_results,zero_results,checks);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1,"%s: global timeout",CASE_NAME);
    end
endmodule
`default_nettype wire
