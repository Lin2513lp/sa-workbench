`timescale 1ns/1ps
`default_nettype none
module tb_tpu_ctrl;
    // 1. DUT 接口：CPU、FIFO 输入、模拟 SA 反馈，以及 CTRL 输出。
    logic sys_ckg;
    logic tpu_rst_n, cpu_tpu_en, cpu_tpu_start;
    logic [1:0] cpu_cpt_mode;
    logic [3:0] cpu_h_size, cpu_w_size;
    logic fifo_empty, fifo_in_rd_dat_last;
    logic [511:0] fifo_in_rdata;
    logic data_out_last;
    logic done_clear_ack;
    logic fifo_in_re, cpu_tpu_en_sync, cpu_tpu_start_sync;
    logic [511:0] dat_in_a;
    logic dat_in_vld, dat_in_last, rpt_cpt_done, rpt_error;
    logic [31:0] rpt_dat_in_cnt;
    logic [2:0] rpt_error_state;

    // 检查器只需循环下标、当前期望值和总检查次数，不保存历史数据。
    integer t, lane, expected_word;
    integer checks_count = 0;
    // 仅用于日志：拼出本拍512bit期望值，不保存历史数据。
    logic [511:0] expected_data;
`ifdef FSDB_TRACE
    string wave_file;
`elsif VCD_TRACE
    string wave_file;
`endif

    // 2. 显式例化 DUT：每个端口都写出对应的 TB 信号。
    tpu_ctrl dut (
        .sys_ckg(sys_ckg),
        .tpu_rst_n(tpu_rst_n),
        .cpu_tpu_en(cpu_tpu_en),
        .cpu_tpu_start(cpu_tpu_start),
        .cpu_done_clear_req(1'b0),
        .done_clear_ack(done_clear_ack),
        .cpu_cpt_mode(cpu_cpt_mode),
        .cpu_h_size(cpu_h_size),
        .cpu_w_size(cpu_w_size),
        .fifo_empty(fifo_empty),
        .fifo_in_rdata(fifo_in_rdata),
        .fifo_in_rd_dat_last(fifo_in_rd_dat_last),
        .data_out_last(data_out_last),
        .fifo_in_re(fifo_in_re),
        .cpu_tpu_en_sync(cpu_tpu_en_sync),
        .cpu_tpu_start_sync(cpu_tpu_start_sync),
        .dat_in_a(dat_in_a),
        .dat_in_vld(dat_in_vld),
        .dat_in_last(dat_in_last),
        .rpt_cpt_done(rpt_cpt_done),
        .rpt_dat_in_cnt(rpt_dat_in_cnt),
        .rpt_error(rpt_error),
        .rpt_error_state(rpt_error_state)
    );

    // 3. 产生 400 MHz 时钟。复位在下面主 initial 中赋值。
    initial sys_ckg = 0;
    always #1.25 sys_ckg = ~sys_ckg;

    // 4. 三种尺寸分开写；只改变H/W配置，每种都送相同16包，mode固定为0。
    initial begin
`ifdef FSDB_TRACE
        if (!$value$plusargs("FSDB_FILE=%s", wave_file)) wave_file = "tb_tpu_ctrl.fsdb";
        $fsdbDumpfile(wave_file);
        $fsdbDumpvars(0, tb_tpu_ctrl, "+all");
`elsif VCD_TRACE
        if (!$value$plusargs("VCD_FILE=%s", wave_file)) wave_file = "tb_tpu_ctrl.vcd";
        $dumpfile(wave_file);
        $dumpvars(0, tb_tpu_ctrl);
`endif
        tpu_rst_n = 0;
        cpu_tpu_en = 0; cpu_tpu_start = 0;
        cpu_cpt_mode = 0; cpu_h_size = 0; cpu_w_size = 0;
        fifo_empty = 1; fifo_in_rdata = 0; fifo_in_rd_dat_last = 0;
        data_out_last = 0;
        repeat (3) @(negedge sys_ckg);
        tpu_rst_n = 1;
        repeat (3) @(negedge sys_ckg);
        checks_count++;
        if (rpt_dat_in_cnt !== 0 || rpt_cpt_done !== 0 || dat_in_a !== 0)
            $fatal(1, "Reset outputs incorrect");

        // ==================== 情况：H=W=1 ====================
        // 尺寸寄存器填尺寸-1；H/W不改变16路补0、对齐或FIFO读取。
        cpu_h_size = 4'd0; cpu_w_size = 4'd0;
        cpu_tpu_en = 1; cpu_tpu_start = 0;
        repeat (4) @(negedge sys_ckg);
        cpu_tpu_start = 1;
        repeat (4) @(negedge sys_ckg);
        checks_count++;
        if (cpu_tpu_en_sync !== 1 || cpu_tpu_start_sync !== 1 || rpt_dat_in_cnt !== 0)
            $fatal(1, "H=W=1: START/synchronization/count incorrect");

        // 前16拍送16包，随后15拍补0，直到第15路最后一个数送出。
        for (t = 0; t < 31; t = t + 1) begin
            fifo_empty = (t >= 16);
            fifo_in_rd_dat_last = (t == 15);
            for (lane = 0; lane < 16; lane = lane + 1)
                fifo_in_rdata[lane*32 +: 32] = (t < 16) ? (t+1)*100+lane+1 : 0;

            // 上升沿、NBA更新前检查：这正是SA在此沿采到的一整列。
            @(posedge sys_ckg);
            for (lane = 0; lane < 16; lane = lane + 1) begin
                // 第lane路来自第(t-lane)包，范围外直接期望0。
                expected_word = (t >= lane && t-lane < 16) ? (t-lane+1)*100+lane+1 : 0;
                expected_data[lane*32 +: 32] = 32'(expected_word);
                checks_count++;
                if (dat_in_a[lane*32 +: 32] !== 32'(expected_word))
                    $fatal(1, "H=W=1: t=%0d lane=%0d actual=%0d expected=%0d",
                           t, lane, dat_in_a[lane*32 +: 32], expected_word);
            end
            checks_count += 3;
            // 十六进制整总线：左侧为lane15，右侧为lane0；采样点同上述校验。
            $display("CTRL_HEX H=W=1 t=%0d read=%b input=%0128h expected=%0128h actual=%0128h valid=%b last=%b",
                     t, fifo_in_re, fifo_in_rdata, expected_data, dat_in_a, dat_in_vld, dat_in_last);
            if (fifo_in_re !== (t < 16)) $fatal(1, "H=W=1: FIFO read t=%0d", t);
            if (dat_in_vld !== 1'b1) $fatal(1, "H=W=1: VALID t=%0d", t);
            if (dat_in_last !== (t == 30)) $fatal(1, "H=W=1: LAST t=%0d", t);

            // 下降沿寄存器已更新：读一包计数加1，尾巴阶段维持16；计数来自实际读取次数，与H/W无关。
            @(negedge sys_ckg);
            checks_count += 3;
            if (rpt_dat_in_cnt !== 32'((t < 16) ? t+1 : 16))
                $fatal(1, "H=W=1: reported input count t=%0d", t);
            if (rpt_cpt_done !== 0) $fatal(1, "H=W=1: premature DONE");
            if (rpt_error !== 0 || rpt_error_state !== 0)
                $fatal(1, "H=W=1: unexpected protocol error");
        end
        fifo_empty = 1; fifo_in_rdata = 0; fifo_in_rd_dat_last = 0;
        checks_count++;
        if (dat_in_a !== 0 || dat_in_vld !== 0 || dat_in_last !== 0)
            $fatal(1, "H=W=1: skew tail did not clear");

        // 输入尾巴已结束，模拟SA最终LAST；下一采样沿置位并保持DONE。
        data_out_last = 1;
        @(negedge sys_ckg);
        checks_count++;
        if (rpt_cpt_done !== 1 || rpt_dat_in_cnt !== 32'd16)
            $fatal(1, "H=W=1: DONE/final input count incorrect");
        data_out_last = 0;
        @(negedge sys_ckg);
        checks_count++;
        if (rpt_cpt_done !== 1 || fifo_in_re !== 0)
            $fatal(1, "H=W=1: DONE must remain set; held START must not restart");
        $display("CTRL_CASE_PASS H=W=1 packets=16 skew_columns=31");

        // ==================== 情况：H=W=4 ====================
        // 尺寸寄存器填尺寸-1；H/W不改变16路补0、对齐或FIFO读取。
        cpu_h_size = 4'd3; cpu_w_size = 4'd3;
        cpu_tpu_en = 1; cpu_tpu_start = 0;
        repeat (4) @(negedge sys_ckg);
        cpu_tpu_start = 1;
        repeat (4) @(negedge sys_ckg);
        checks_count++;
        if (cpu_tpu_en_sync !== 1 || cpu_tpu_start_sync !== 1 || rpt_dat_in_cnt !== 0)
            $fatal(1, "H=W=4: START/synchronization/count incorrect");

        // 前16拍送16包，随后15拍补0，直到第15路最后一个数送出。
        for (t = 0; t < 31; t = t + 1) begin
            fifo_empty = (t >= 16);
            fifo_in_rd_dat_last = (t == 15);
            for (lane = 0; lane < 16; lane = lane + 1)
                fifo_in_rdata[lane*32 +: 32] = (t < 16) ? (t+1)*100+lane+1 : 0;

            // 上升沿、NBA更新前检查：这正是SA在此沿采到的一整列。
            @(posedge sys_ckg);
            for (lane = 0; lane < 16; lane = lane + 1) begin
                // 第lane路来自第(t-lane)包，范围外直接期望0。
                expected_word = (t >= lane && t-lane < 16) ? (t-lane+1)*100+lane+1 : 0;
                expected_data[lane*32 +: 32] = 32'(expected_word);
                checks_count++;
                if (dat_in_a[lane*32 +: 32] !== 32'(expected_word))
                    $fatal(1, "H=W=4: t=%0d lane=%0d actual=%0d expected=%0d",
                           t, lane, dat_in_a[lane*32 +: 32], expected_word);
            end
            checks_count += 3;
            // 十六进制整总线：左侧为lane15，右侧为lane0；采样点同上述校验。
            $display("CTRL_HEX H=W=4 t=%0d read=%b input=%0128h expected=%0128h actual=%0128h valid=%b last=%b",
                     t, fifo_in_re, fifo_in_rdata, expected_data, dat_in_a, dat_in_vld, dat_in_last);
            if (fifo_in_re !== (t < 16)) $fatal(1, "H=W=4: FIFO read t=%0d", t);
            if (dat_in_vld !== 1'b1) $fatal(1, "H=W=4: VALID t=%0d", t);
            if (dat_in_last !== (t == 30)) $fatal(1, "H=W=4: LAST t=%0d", t);

            // 下降沿寄存器已更新：读一包计数加1，尾巴阶段维持16；计数来自实际读取次数，与H/W无关。
            @(negedge sys_ckg);
            checks_count += 3;
            if (rpt_dat_in_cnt !== 32'((t < 16) ? t+1 : 16))
                $fatal(1, "H=W=4: reported input count t=%0d", t);
            if (rpt_cpt_done !== 0) $fatal(1, "H=W=4: premature DONE");
            if (rpt_error !== 0 || rpt_error_state !== 0)
                $fatal(1, "H=W=4: unexpected protocol error");
        end
        fifo_empty = 1; fifo_in_rdata = 0; fifo_in_rd_dat_last = 0;
        checks_count++;
        if (dat_in_a !== 0 || dat_in_vld !== 0 || dat_in_last !== 0)
            $fatal(1, "H=W=4: skew tail did not clear");

        // 输入尾巴已结束，模拟SA最终LAST；下一采样沿置位并保持DONE。
        data_out_last = 1;
        @(negedge sys_ckg);
        checks_count++;
        if (rpt_cpt_done !== 1 || rpt_dat_in_cnt !== 32'd16)
            $fatal(1, "H=W=4: DONE/final input count incorrect");
        data_out_last = 0;
        @(negedge sys_ckg);
        checks_count++;
        if (rpt_cpt_done !== 1 || fifo_in_re !== 0)
            $fatal(1, "H=W=4: DONE must remain set; held START must not restart");
        $display("CTRL_CASE_PASS H=W=4 packets=16 skew_columns=31");

        // ==================== 情况：H=W=16 ====================
        // 尺寸寄存器填尺寸-1；H/W不改变16路补0、对齐或FIFO读取。
        cpu_h_size = 4'd15; cpu_w_size = 4'd15;
        cpu_tpu_en = 1; cpu_tpu_start = 0;
        repeat (4) @(negedge sys_ckg);
        cpu_tpu_start = 1;
        repeat (4) @(negedge sys_ckg);
        checks_count++;
        if (cpu_tpu_en_sync !== 1 || cpu_tpu_start_sync !== 1 || rpt_dat_in_cnt !== 0)
            $fatal(1, "H=W=16: START/synchronization/count incorrect");

        // 前16拍送16包，随后15拍补0，直到第15路最后一个数送出。
        for (t = 0; t < 31; t = t + 1) begin
            fifo_empty = (t >= 16);
            fifo_in_rd_dat_last = (t == 15);
            for (lane = 0; lane < 16; lane = lane + 1)
                fifo_in_rdata[lane*32 +: 32] = (t < 16) ? (t+1)*100+lane+1 : 0;

            // 上升沿、NBA更新前检查：这正是SA在此沿采到的一整列。
            @(posedge sys_ckg);
            for (lane = 0; lane < 16; lane = lane + 1) begin
                // 第lane路来自第(t-lane)包，范围外直接期望0。
                expected_word = (t >= lane && t-lane < 16) ? (t-lane+1)*100+lane+1 : 0;
                expected_data[lane*32 +: 32] = 32'(expected_word);
                checks_count++;
                if (dat_in_a[lane*32 +: 32] !== 32'(expected_word))
                    $fatal(1, "H=W=16: t=%0d lane=%0d actual=%0d expected=%0d",
                           t, lane, dat_in_a[lane*32 +: 32], expected_word);
            end
            checks_count += 3;
            // 十六进制整总线：左侧为lane15，右侧为lane0；采样点同上述校验。
            $display("CTRL_HEX H=W=16 t=%0d read=%b input=%0128h expected=%0128h actual=%0128h valid=%b last=%b",
                     t, fifo_in_re, fifo_in_rdata, expected_data, dat_in_a, dat_in_vld, dat_in_last);
            if (fifo_in_re !== (t < 16)) $fatal(1, "H=W=16: FIFO read t=%0d", t);
            if (dat_in_vld !== 1'b1) $fatal(1, "H=W=16: VALID t=%0d", t);
            if (dat_in_last !== (t == 30)) $fatal(1, "H=W=16: LAST t=%0d", t);

            // 下降沿寄存器已更新：读一包计数加1，尾巴阶段维持16；计数来自实际读取次数，与H/W无关。
            @(negedge sys_ckg);
            checks_count += 3;
            if (rpt_dat_in_cnt !== 32'((t < 16) ? t+1 : 16))
                $fatal(1, "H=W=16: reported input count t=%0d", t);
            if (rpt_cpt_done !== 0) $fatal(1, "H=W=16: premature DONE");
            if (rpt_error !== 0 || rpt_error_state !== 0)
                $fatal(1, "H=W=16: unexpected protocol error");
        end
        fifo_empty = 1; fifo_in_rdata = 0; fifo_in_rd_dat_last = 0;
        checks_count++;
        if (dat_in_a !== 0 || dat_in_vld !== 0 || dat_in_last !== 0)
            $fatal(1, "H=W=16: skew tail did not clear");

        // 输入尾巴已结束，模拟SA最终LAST；下一采样沿置位并保持DONE。
        data_out_last = 1;
        @(negedge sys_ckg);
        checks_count++;
        if (rpt_cpt_done !== 1 || rpt_dat_in_cnt !== 32'd16)
            $fatal(1, "H=W=16: DONE/final input count incorrect");
        data_out_last = 0;
        @(negedge sys_ckg);
        checks_count++;
        if (rpt_cpt_done !== 1 || fifo_in_re !== 0)
            $fatal(1, "H=W=16: DONE must remain set; held START must not restart");
        $display("CTRL_CASE_PASS H=W=16 packets=16 skew_columns=31");

        $display("CTRL_UNIT_PASS checks=%0d cases=3 packets=48", checks_count);
        $finish;
    end
endmodule
`default_nettype wire
