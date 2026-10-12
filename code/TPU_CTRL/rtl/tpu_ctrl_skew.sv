`timescale 1ns/1ps
`default_nettype none

// Physical 16-lane bus: lane r is delayed r SYS clocks. Empty FIFO clocks
// advance zero bubbles, rather than stopping the PE wavefront downstream.
module tpu_ctrl_skew #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned LANES = 16
) (
    input  wire logic sys_ckg,
    input  wire logic tpu_rst_n,
    input  wire logic clear,
    input  wire logic [LANES*DATA_WIDTH-1:0] input_data,
    input  wire logic input_valid,
    input  wire logic input_last,
    output      logic [LANES*DATA_WIDTH-1:0] output_data,
    output      logic output_valid,
    output      logic output_last
);
    logic [LANES-1:0] lane_valid;
    logic [LANES-1:0] lane_last;

    assign lane_valid[0] = input_valid && !clear;
    assign lane_last[0] = input_last && lane_valid[0];
    assign output_data[0 +: DATA_WIDTH] = lane_valid[0] ? input_data[0 +: DATA_WIDTH] : '0;

    for (genvar row = 1; row < LANES; row++) begin : gen_lane
        logic [DATA_WIDTH-1:0] data_q [0:row-1];
        logic [row-1:0] valid_q;
        logic [row-1:0] last_q;
        always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
            if (!tpu_rst_n) begin
                valid_q <= '0;
                last_q <= '0;
                for (int stage = 0; stage < row; stage++) data_q[stage] <= '0;
            end else if (clear) begin
                valid_q <= '0;
                last_q <= '0;
                for (int stage = 0; stage < row; stage++) data_q[stage] <= '0;
            end else begin
                data_q[0] <= input_valid ? input_data[row*DATA_WIDTH +: DATA_WIDTH] : '0;
                valid_q[0] <= input_valid;
                last_q[0] <= input_last && input_valid;
                for (int stage = 1; stage < row; stage++) begin
                    data_q[stage] <= data_q[stage-1];
                    valid_q[stage] <= valid_q[stage-1];
                    last_q[stage] <= last_q[stage-1];
                end
            end
        end
        assign lane_valid[row] = valid_q[row-1] && !clear;
        assign lane_last[row] = last_q[row-1] && !clear;
        assign output_data[row*DATA_WIDTH +: DATA_WIDTH] = lane_valid[row] ? data_q[row-1] : '0;
    end

    // SA has one shared valid. Padding lanes always carry numeric zero.
    assign output_valid = |lane_valid;
    // LAST follows the physical final lane, independent of active H/W.
    assign output_last = lane_last[LANES-1];
endmodule
`default_nettype wire
