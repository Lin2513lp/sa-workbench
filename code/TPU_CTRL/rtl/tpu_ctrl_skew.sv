`timescale 1ns/1ps
`default_nettype none

// 每拍输入一列，默认 16 路 x 32 bit；第 r 路延迟 r 拍。
// 连续输入 P0、P1、P2 时，SA 在 T0 / T1 / T2 上升沿采到：
//   第 0 路： P0[0]  P1[0]  P2[0]
//   第 1 路：   0    P0[1]  P1[1]
//   第 2 路：   0      0    P0[2]
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
    // 1. 先补 0：这一拍没有读到 FIFO，整个输入列直接替换成 0。
    logic [LANES*DATA_WIDTH-1:0] padded_input;
    assign padded_input = input_valid ? input_data : '0;

    // 2. 再错开：第 0 路直通，第 r 路经过 r 级数据寄存器。
    assign output_data[0 +: DATA_WIDTH] = clear ? '0 : padded_input[0 +: DATA_WIDTH];

    for (genvar row = 1; row < LANES; row++) begin : gen_lane
        // row=1：输入 -> data_q[0] -> 输出
        // row=2：输入 -> data_q[0] -> data_q[1] -> 输出
        // row=3：输入 -> data_q[0] -> data_q[1] -> data_q[2] -> 输出
        logic [DATA_WIDTH-1:0] data_q [0:row-1];
        always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
            if (!tpu_rst_n) begin
                for (int stage = 0; stage < row; stage++) data_q[stage] <= '0;
            end else if (clear) begin
                for (int stage = 0; stage < row; stage++) data_q[stage] <= '0;
            end else begin
                // 第一级接收本路数据；无效输入已在前面补成 0。
                data_q[0] <= padded_input[row*DATA_WIDTH +: DATA_WIDTH];
                // 后续级每拍接收前一级旧值，FIFO 为空也不停移位。
                for (int stage = 1; stage < row; stage++)
                    data_q[stage] <= data_q[stage-1];
            end
        end
        // 开头的空位来自复位清零，末尾的空位来自输入补零。
        // clear 立即屏蔽输出，下一上升沿同时清空内部寄存器。
        assign output_data[row*DATA_WIDTH +: DATA_WIDTH] = clear ? '0 : data_q[row-1];
    end

    // 3. 标记跟随数据：共用一条历史链，第 r 位表示延迟 r 拍。
    // 有效数据也可能等于 0，所以 valid 仍需单独保存。
    logic [LANES-1:0] valid_history;
    logic [LANES-1:0] last_history;
    assign valid_history[0] = input_valid;
    assign last_history[0] = input_valid && input_last;
    for (genvar delay = 1; delay < LANES; delay++) begin : gen_marker
        always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
            if (!tpu_rst_n) begin
                valid_history[delay] <= 1'b0;
                last_history[delay] <= 1'b0;
            end else if (clear) begin
                valid_history[delay] <= 1'b0;
                last_history[delay] <= 1'b0;
            end else begin
                valid_history[delay] <= valid_history[delay-1];
                last_history[delay] <= last_history[delay-1];
            end
        end
    end
    // 任意一路有效，整列 valid 就为 1；LAST 跟随物理最后一路。
    assign output_valid = !clear && (|valid_history);
    assign output_last = !clear && last_history[LANES-1];
endmodule
`default_nettype wire
