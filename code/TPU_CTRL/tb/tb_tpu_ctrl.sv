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
    logic data_out_last, sa_pipeline_empty;
    logic fifo_in_re, cpu_tpu_en_sync, cpu_tpu_start_sync;
    logic [511:0] dat_in_a;
    logic dat_in_vld, dat_in_last, rpt_cpt_done, rpt_error;
    logic [31:0] rpt_dat_in_cnt;
    logic [2:0] rpt_error_state;

    // TB 自己记录实际读入的数据，不查看 DUT 内部寄存器。
    logic [511:0] read_history [0:14];
    logic read_valid_history [0:14], read_last_history [0:14];
    logic en_ref_1 = 0, en_ref_2 = 0;
    logic start_ref_1 = 0, start_ref_2 = 0;
    logic expected_valid, expected_last;
    logic [31:0] expected_word;
    logic allow_done = 0;
    int checks_count = 0, pops = 0, last_columns = 0, dones = 0;
    int valid_zero_words = 0;
    int before_pop, before_last, before_done;
    int size, packet_count, gap_period, sent, tick;
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
        .cpu_cpt_mode(cpu_cpt_mode),
        .cpu_h_size(cpu_h_size),
        .cpu_w_size(cpu_w_size),
        .fifo_empty(fifo_empty),
        .fifo_in_rdata(fifo_in_rdata),
        .fifo_in_rd_dat_last(fifo_in_rd_dat_last),
        .data_out_last(data_out_last),
        .sa_pipeline_empty(sa_pipeline_empty),
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

    // 4. 主测试：直接按顺序赋值、送数据、等待、检查，没有 task/function。
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
        // 初始复位：所有输入都明确赋值。
        tpu_rst_n = 0;
        cpu_tpu_en = 0; cpu_tpu_start = 0;
        cpu_cpt_mode = 0; cpu_h_size = 15; cpu_w_size = 15;
        fifo_empty = 1; fifo_in_rdata = '0; fifo_in_rd_dat_last = 0;
        data_out_last = 0; sa_pipeline_empty = 1;
        repeat (3) @(negedge sys_ckg);
        tpu_rst_n = 1;
        repeat (3) @(negedge sys_ckg);

        // 非空 FIFO + EN，但没有 START，不能自动读取。
        cpu_tpu_en = 1; fifo_empty = 0;
        repeat (8) @(negedge sys_ckg);
        checks_count++;
        if (pops != 0 || fifo_in_re) $fatal(1, "EN alone must not start FIFO reads");

        // job 0~11：四种 mode × H=W=1/4/16，每个任务都送足16包。
        // job 12：31包长任务 + 气泡 + 工作中再次 START。
        // job 13：SA LAST 早于第15路输入尾巴。
        // job 14：关闭 EN 中止；job 15：复位后重新送16包。
        // job 16~19：四种 mode 的单包边界，第一包同时就是 LAST。
        for (int job = 0; job < 20; job++) begin
            before_pop = pops; before_last = last_columns; before_done = dones;
            allow_done = 0;
            cpu_cpt_mode = 1; size = 16; packet_count = 16; gap_period = 0;
            if (job < 12) begin
                cpu_cpt_mode = 2'(job/3);
                case (job%3)
                    0: size = 1;
                    1: begin size = 4; gap_period = 3; end
                    2: size = 16;
                endcase
            end
            if (job == 12) begin packet_count = 31; gap_period = 5; end
            if (job == 13) size = 4;
            if (job == 14) packet_count = 8;
            if (job >= 16) begin
                cpu_cpt_mode = 2'(job-16); size = 1; packet_count = 1;
            end
            cpu_h_size = 4'(size-1); cpu_w_size = 4'(size-1);

            // 先使能，再启动；所有激励在下降沿改变，避开 DUT 采样沿。
            fifo_empty = 1; fifo_in_rd_dat_last = 0; data_out_last = 0;
            sa_pipeline_empty = 1;
            cpu_tpu_en = 1; cpu_tpu_start = 0;
            repeat (4) @(negedge sys_ckg);
            cpu_tpu_start = 1;
            repeat (4) @(negedge sys_ckg);
            checks_count++;
            if (rpt_dat_in_cnt !== 0) $fatal(1, "New START must clear input count");

            sent = 0; tick = 0;
            while (sent < packet_count) begin
                fifo_empty = (gap_period > 0 && tick%gap_period == 1);
                for (int lane = 0; lane < 16; lane++) begin
                    // 每任务、每包、每路的数据不同；特意包含有效数值0。
                    fifo_in_rdata[lane*32 +: 32] =
                        (sent%7 == 0 && lane%5 == 0) ? 32'b0
                        : 32'((job+1)*100000 + (sent+1)*1000 + lane*37);
                end
                fifo_in_rd_dat_last = (sent == packet_count-1 && job != 14);
                data_out_last = (tick == 0); // 输入尚未结束的 SA 标记必须忽略。
                if (job == 12 && tick == 3) cpu_tpu_start = 0;
                if (job == 12 && tick == 7) cpu_tpu_start = 1;
                @(posedge sys_ckg);
                if (fifo_in_re) sent++;
                @(negedge sys_ckg);
                tick++;
                checks_count++;
                if (rpt_dat_in_cnt !== 32'(sent)) $fatal(1, "Input count actual=%0d expected=%0d",
                                                    rpt_dat_in_cnt, sent);
                if (tick > 500) $fatal(1, "FIFO input timeout");
            end
            fifo_in_rd_dat_last = 0; data_out_last = 0;

            if (job == 14) begin
                // 没送 LAST，且还有在途数据；EN 经两拍同步后必须清空。
                cpu_tpu_en = 0; fifo_empty = 1;
                repeat (20) @(negedge sys_ckg);
                checks_count++;
                if (dat_in_vld || dat_in_a !== 0 || dat_in_last || dones != before_done)
                    $fatal(1, "Disable must discard unfinished task");
                tpu_rst_n = 0; cpu_tpu_start = 0;
                repeat (3) @(negedge sys_ckg);
                tpu_rst_n = 1;
                repeat (3) @(negedge sys_ckg);
                $display("CTRL_CASE_PASS job=%0d abort=1 packets=%0d", job, packet_count);
            end else begin
                // LAST 后摆出下一任务头部，CTRL 必须停止读取它。
                fifo_empty = 0; fifo_in_rdata = {16{32'hDEADBEEF}};
                if (job == 13) begin
                    repeat (3) @(negedge sys_ckg);
                    checks_count++;
                    if (last_columns != before_last || dones != before_done)
                        $fatal(1, "Early-SA case must still have input tail in flight");
                    data_out_last = 1; allow_done = 1;
                    @(negedge sys_ckg);
                    data_out_last = 0;
                    checks_count++;
                    if (dones != before_done) $fatal(1, "Early SA LAST must wait input tail");
                end
                repeat (20) begin
                    @(negedge sys_ckg);
                    checks_count++;
                    if (fifo_in_re) $fatal(1, "Must stop reading at input LAST");
                end
                checks_count += 3;
                if (pops-before_pop != packet_count) $fatal(1, "FIFO packet count mismatch");
                if (rpt_dat_in_cnt !== 32'(packet_count)) $fatal(1, "Final reported count mismatch");
                if (last_columns-before_last != 1) $fatal(1, "Must emit exactly one input tail LAST");

                if (job != 13) begin
                    checks_count++;
                    if (dones != before_done) $fatal(1, "Must wait for genuine SA LAST");
                    data_out_last = 1; sa_pipeline_empty = 0;
                    repeat (2) @(negedge sys_ckg);
                    data_out_last = 0;
                    repeat (3) @(negedge sys_ckg);
                    checks_count++;
                    if (dones != before_done) $fatal(1, "SA LAST cannot bypass busy pipeline");
                    sa_pipeline_empty = 1; allow_done = 1;
                end
                repeat (5) @(negedge sys_ckg);
                checks_count += 2;
                if (dones-before_done != 1) $fatal(1, "Must produce one DONE pulse");
                if (fifo_in_re) $fatal(1, "Held START must not retrigger");
                $display("CTRL_CASE_PASS job=%0d mode=%0d H=W=%0d packets=%0d gap=%0d early_last=%0d",
                         job, cpu_cpt_mode, size, packet_count, gap_period, job == 13);
                cpu_tpu_start = 0;
                repeat (4) @(negedge sys_ckg);
            end
        end
        if (dones != 19 || last_columns != 19 || valid_zero_words == 0)
            $fatal(1, "Incomplete tests or valid zero data not exercised");
        $display("CTRL_UNIT_PASS checks=%0d pops=%0d last_columns=%0d dones=%0d valid_zero_words=%0d",
                 checks_count, pops, last_columns, dones, valid_zero_words);
        $finish;
    end

    // 5. 每个上升沿自动检查：第 r 路 = r 拍前实际读入的第 r 个数。
    // 在 DUT 非阻塞赋值更新前检查，正好对应 SA 在该沿采样的数据。
    always @(posedge sys_ckg) begin
        if (!tpu_rst_n || !cpu_tpu_en_sync) begin
            for (int past = 0; past < 15; past++) begin
                read_history[past] = '0;
                read_valid_history[past] = 0;
                read_last_history[past] = 0;
            end
        end
        if (tpu_rst_n) begin
            expected_valid = fifo_in_re;
            expected_last = read_last_history[14];
            for (int lane = 0; lane < 16; lane++) begin
                if (lane == 0)
                    expected_word = fifo_in_re ? fifo_in_rdata[31:0] : 32'b0;
                else begin
                    expected_word = read_valid_history[lane-1]
                        ? read_history[lane-1][lane*32 +: 32] : 32'b0;
                    expected_valid |= read_valid_history[lane-1];
                end
                checks_count++;
                if (dat_in_a[lane*32 +: 32] !== expected_word)
                    $fatal(1, "DATA lane=%0d actual=%h expected=%h time=%0t",
                           lane, dat_in_a[lane*32 +: 32], expected_word, $time);
                if (expected_word == 0 && ((lane == 0 && fifo_in_re) ||
                    (lane > 0 && read_valid_history[lane-1])))
                    valid_zero_words++;
            end
            checks_count += 4;
            if (dat_in_vld !== expected_valid) $fatal(1, "VALID mismatch");
            if (dat_in_last !== expected_last) $fatal(1, "LAST must follow lane15");
            if (fifo_in_re && (fifo_empty || !cpu_tpu_en_sync))
                $fatal(1, "FIFO read while empty or disabled");
            if (rpt_error !== 0 || rpt_error_state !== 0)
                $fatal(1, "Reserved error outputs must remain zero");
            if (fifo_in_re) pops++;
            if (dat_in_last) last_columns++;
            if (rpt_cpt_done) begin
                dones++;
                checks_count++;
                if (!allow_done || last_columns != before_last + 1)
                    $fatal(1, "DONE before permitted SA completion/input tail");
            end
        end

        // 每个时钟都记录；没有读取的时钟也占一格，表示气泡。
        // 阻塞赋值从后往前移动，防止覆盖尚未使用的历史值。
        for (int past = 14; past > 0; past--) begin
            read_history[past] = read_history[past-1];
            read_valid_history[past] = read_valid_history[past-1];
            read_last_history[past] = read_last_history[past-1];
        end
        read_history[0] = fifo_in_re ? fifo_in_rdata : '0;
        read_valid_history[0] = fifo_in_re;
        read_last_history[0] = fifo_in_re && fifo_in_rd_dat_last;

        // 独立两拍同步参考值；稍后检查 DUT 更新后的输出。
        if (!tpu_rst_n) begin
            en_ref_1 = 0; en_ref_2 = 0;
            start_ref_1 = 0; start_ref_2 = 0;
        end else begin
            en_ref_2 = en_ref_1; en_ref_1 = cpu_tpu_en;
            start_ref_2 = start_ref_1; start_ref_1 = cpu_tpu_start;
        end
        #0.1;
        checks_count += 2;
        if (cpu_tpu_en_sync !== en_ref_2) $fatal(1, "EN two-stage CDC mismatch");
        if (cpu_tpu_start_sync !== start_ref_2) $fatal(1, "START two-stage CDC mismatch");
    end

    // 超时保护，避免错误时永远等待。
    initial begin
        #200000;
        $fatal(1, "CTRL unit global timeout");
    end
endmodule
`default_nettype wire
