`timescale 1ns/1ps
`default_nettype none

module tpu_ctrl (
    // Always-on control while a task/CDC handshake is in progress; SYS clock
    // gating and reset release remain the external CRG responsibility.
    input  wire logic sys_ckg,
    input  wire logic tpu_rst_n,
    input  wire logic cpu_tpu_en,
    input  wire logic cpu_tpu_start,
    // Bundled static configuration: keep stable before START through DONE.
    input  wire logic [1:0] cpu_cpt_mode,
    input  wire logic [3:0] cpu_h_size,
    input  wire logic [3:0] cpu_w_size,
    input  wire logic fifo_empty,
    input  wire logic [511:0] fifo_in_rdata,
    input  wire logic fifo_in_rd_dat_last,
    // Wire SA dat_out_vld && dat_out_last here. This is SA completion, not
    // acknowledgment by the AXI output consumer.
    input  wire logic data_out_last,
    // Actual bottom-row PE-valid reduction from SA. Useful output LAST can
    // precede valid padding; keep the task alive until that pipeline drains.
    input  wire logic sa_pipeline_empty,
    output      logic fifo_in_re,
    output      logic cpu_tpu_en_sync,
    output      logic cpu_tpu_start_sync,
    output      logic [511:0] dat_in_a,
    output      logic dat_in_vld,
    output      logic dat_in_last,
    output      logic rpt_cpt_done,
    output      logic [31:0] rpt_dat_in_cnt,
    output      logic rpt_error,
    output      logic [2:0] rpt_error_state
);
    logic start_prev_q;
    logic task_active_q;
    logic input_last_seen_q;
    logic skew_last_seen_q;
    logic output_last_seen_q;
    logic start_accept;
    logic skew_clear;
    // H/W affect SA PE masks, never the physical CTRL skew width or delay.
    // Precision arithmetic is owned by SA; every mode uses the same skew.
    logic unused_static_config;
    assign unused_static_config = ^{cpu_cpt_mode, cpu_h_size, cpu_w_size};

    tpu_ctrl_sync u_sync (
        .sys_ckg, .tpu_rst_n, .cpu_tpu_en, .cpu_tpu_start,
        .cpu_tpu_en_sync, .cpu_tpu_start_sync
    );

    assign start_accept = cpu_tpu_en_sync && cpu_tpu_start_sync &&
                          !start_prev_q && !task_active_q;
    assign fifo_in_re = tpu_rst_n && cpu_tpu_en_sync && task_active_q &&
                        !input_last_seen_q && !fifo_empty;
    assign skew_clear = !cpu_tpu_en_sync || !task_active_q || start_accept;
    tpu_ctrl_skew u_skew (
        .sys_ckg, .tpu_rst_n, .clear(skew_clear),
        .input_data(fifo_in_rdata), .input_valid(fifo_in_re),
        .input_last(fifo_in_rd_dat_last),
        .output_data(dat_in_a), .output_valid(dat_in_vld),
        .output_last(dat_in_last)
    );

    // No FSM: task and completion flags delimit the stream.
    // Rising START during a task is ignored. A held-high START never retriggers.
    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            start_prev_q <= 1'b0;
            task_active_q <= 1'b0;
            input_last_seen_q <= 1'b0;
            skew_last_seen_q <= 1'b0;
            output_last_seen_q <= 1'b0;
            rpt_dat_in_cnt <= '0;
            rpt_cpt_done <= 1'b0;
        end else begin
            start_prev_q <= cpu_tpu_start_sync;
            rpt_cpt_done <= 1'b0;
            if (!cpu_tpu_en_sync) begin
                task_active_q <= 1'b0;
                input_last_seen_q <= 1'b0;
                skew_last_seen_q <= 1'b0;
                output_last_seen_q <= 1'b0;
            end else if (start_accept) begin
                task_active_q <= 1'b1;
                input_last_seen_q <= 1'b0;
                skew_last_seen_q <= 1'b0;
                output_last_seen_q <= 1'b0;
                rpt_dat_in_cnt <= '0;
            end else if (task_active_q) begin
                if (fifo_in_re) begin
                    rpt_dat_in_cnt <= rpt_dat_in_cnt + 32'd1;
                    if (fifo_in_rd_dat_last) input_last_seen_q <= 1'b1;
                end
                if (dat_in_vld && dat_in_last) skew_last_seen_q <= 1'b1;
                // Small H/W completes useful C before the physical 16-lane
                // input tail. Remember SA completion without dropping that
                // tail, and complete once both ends have been sampled.
                // Ignore LAST on the FIFO LAST edge itself: even H=W=L=1
                // returns its PE result to CTRL at the following edge.
                if (data_out_last && input_last_seen_q)
                    output_last_seen_q <= 1'b1;
                if ((skew_last_seen_q || (dat_in_vld && dat_in_last)) &&
                    (output_last_seen_q || (data_out_last && input_last_seen_q)) &&
                    sa_pipeline_empty) begin
                    rpt_cpt_done <= 1'b1;
                    task_active_q <= 1'b0;
                end
            end
        end
    end

    // Reserved until the user specifies missing-data/error classification.
    assign rpt_error = 1'b0;
    assign rpt_error_state = 3'b000;
endmodule
`default_nettype wire
