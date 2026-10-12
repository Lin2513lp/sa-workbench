`timescale 1ns/1ps
`default_nettype none
module tb_tpu_ctrl;
    // 独立 CTRL 单元测试：FIFO 头部和 SA 的 LAST/EMPTY 由 TB 驱动。
    // 本测试不实例化 SA，不能替代真实 FIFO_IN + CTRL + SA 的矩阵联调。
    // 所有 size 配置通过同一个参数写入 H/W，始终满足 H=W。
`ifdef FSDB_TRACE
    string fsdb_file_runtime;
    initial begin
        if (!$value$plusargs("FSDB_FILE=%s", fsdb_file_runtime))
            fsdb_file_runtime = "tb_tpu_ctrl.fsdb";
        $fsdbDumpfile(fsdb_file_runtime);
        $fsdbDumpvars(0, tb_tpu_ctrl, "+all");
    end
`elsif VCD_TRACE
    string vcd_file_runtime;
    initial begin
        if (!$value$plusargs("VCD_FILE=%s", vcd_file_runtime))
            vcd_file_runtime = "tb_tpu_ctrl.vcd";
        $dumpfile(vcd_file_runtime);
        $dumpvars(0, tb_tpu_ctrl);
    end
`endif
    logic sys_ckg = 0;
    always #1.25 sys_ckg = !sys_ckg;
    logic tpu_rst_n=0, cpu_tpu_en=0, cpu_tpu_start=0;
    logic [1:0] cpu_cpt_mode=1;
    logic [3:0] cpu_h_size=15, cpu_w_size=15;
    logic fifo_empty=1, fifo_in_rd_dat_last=0, data_out_last=0;
    logic sa_pipeline_empty=1;
    logic [511:0] fifo_in_rdata='0;
    logic fifo_in_re, cpu_tpu_en_sync, cpu_tpu_start_sync;
    logic [511:0] dat_in_a;
    logic dat_in_vld, dat_in_last, rpt_cpt_done, rpt_error;
    logic [31:0] rpt_dat_in_cnt;
    logic [2:0] rpt_error_state;
    tpu_ctrl dut (.*);

    logic [511:0] history_data[0:14];
    logic history_valid[0:14], history_last[0:14];
    logic ref_en1=0, ref_en2=0, ref_start1=0, ref_start2=0;
    int checks_count=0, pops=0, last_columns=0, dones=0;
    int expected_count=0;
    logic expected_valid, expected_last;
    logic [31:0] expected_word;

    task automatic check(input logic ok, input string reason);
        checks_count++;
        if (!ok) $fatal(1,"UNIT %s",reason);
    endtask
    function automatic logic [511:0] make_beat(input int tag);
        for(int row=0;row<16;row++)
            make_beat[row*32 +:32] = 32'((tag+1)*1000+row*37);
    endfunction

    // Independent time-history oracle: output lane r must equal the word
    // actually consumed r clocks ago, including clocks with no FIFO read.
    always @(posedge sys_ckg) begin
        if (!tpu_rst_n || !cpu_tpu_en_sync) begin
            for(int j=0;j<15;j++) begin
                history_data[j]='0; history_valid[j]=0; history_last[j]=0;
            end
        end
        if(tpu_rst_n) begin
            expected_valid=fifo_in_re;
            expected_last=history_last[14];
            for(int row=0;row<16;row++) begin
                if(row==0) expected_word=fifo_in_re ? fifo_in_rdata[0+:32] : 0;
                else begin
                    expected_word=history_valid[row-1] ? history_data[row-1][row*32+:32] : 0;
                    expected_valid |= history_valid[row-1];
                end
                check(dat_in_a[row*32+:32]===expected_word,
                    $sformatf("lane%0d got%h expected%h",row,dat_in_a[row*32+:32],expected_word));
            end
            check(dat_in_vld===expected_valid,"shared valid timing");
            check(dat_in_last===expected_last,"last must follow physical lane15");
            check(!fifo_in_re || (!fifo_empty && cpu_tpu_en_sync),"read gate");
            if(fifo_in_re) begin pops++; expected_count++; end
            if(dat_in_last) last_columns++;
            if(rpt_cpt_done) begin
                dones++;
                // The tail was checked in a preceding clock, never FIFO LAST alone.
                check(last_columns>0,"premature done");
            end
        end
        for(int j=14;j>0;j--) begin
            history_data[j]=history_data[j-1];
            history_valid[j]=history_valid[j-1];
            history_last[j]=history_last[j-1];
        end
        history_data[0]=fifo_in_re ? fifo_in_rdata : '0;
        history_valid[0]=fifo_in_re;
        history_last[0]=fifo_in_re && fifo_in_rd_dat_last;
        if(!tpu_rst_n) begin
            ref_en1=0; ref_en2=0; ref_start1=0; ref_start2=0;
        end else begin
            ref_en2=ref_en1; ref_en1=cpu_tpu_en;
            ref_start2=ref_start1; ref_start1=cpu_tpu_start;
        end
        #0.1;
        check(cpu_tpu_en_sync===ref_en2,"enable must cross exactly2 FF stages");
        check(cpu_tpu_start_sync===ref_start2,"start must cross exactly2 FF stages");
    end

    task automatic reset;
        @(negedge sys_ckg);
        tpu_rst_n=0; cpu_tpu_start=0; cpu_tpu_en=0;
        fifo_empty=1; fifo_in_rd_dat_last=0; data_out_last=0;
        repeat(3) @(negedge sys_ckg);
        tpu_rst_n=1;
        repeat(3) @(negedge sys_ckg);
    endtask
    task automatic start;
        fifo_empty=1;
        cpu_tpu_en=1;
        repeat(4) @(negedge sys_ckg);
        cpu_tpu_start=1;
        repeat(4) @(negedge sys_ckg);
        expected_count=0;
        check(rpt_dat_in_cnt==0,"counter resets on accepted start");
    endtask

    task automatic run_task(input int length,input int gap_period,input int mode,input int size);
        int before_pop, before_last, before_done, sent, tick;
        before_pop=pops; before_last=last_columns; before_done=dones;
        cpu_cpt_mode=2'(mode); cpu_h_size=4'(size-1); cpu_w_size=4'(size-1);
        start(); sent=0; tick=0;
        while(sent<length) begin
            fifo_empty=(gap_period>0 && tick%gap_period==1);
            fifo_in_rdata=make_beat(sent);
            fifo_in_rd_dat_last=(sent==length-1);
            // A premature SA marker must not finish a task.
            data_out_last=(tick==0);
            // A new START edge during a task must not clear its count/skew.
            if(length==31 && tick==3) cpu_tpu_start=0;
            if(length==31 && tick==7) cpu_tpu_start=1;
            @(posedge sys_ckg);
            if(fifo_in_re) sent++;
            @(negedge sys_ckg);
            tick++;
            check(tick<500,"input timeout");
        end
        fifo_empty=0; fifo_in_rdata=make_beat(999); fifo_in_rd_dat_last=0; data_out_last=0;
        // Keep a following task head visible; it must remain unconsumed.
        repeat(20) begin
            @(negedge sys_ckg);
            check(!fifo_in_re,"must stop at FIFO LAST despite next visible head");
        end
        check(pops-before_pop==length,"exact FIFO pop count");
        check(rpt_dat_in_cnt==32'(length),"reported input count");
        check(last_columns-before_last==1,"exactly one skew tail last");
        check(dones==before_done,"must wait for real SA output last");
        data_out_last=1;
        sa_pipeline_empty=0;
        repeat(2) @(negedge sys_ckg);
        data_out_last=0;
        repeat(3) @(negedge sys_ckg);
        check(dones==before_done,"must wait for SA pipeline empty after output LAST");
        sa_pipeline_empty=1;
        repeat(5) @(negedge sys_ckg);
        check(dones-before_done==1,"one completion pulse");
        check(!fifo_in_re,"held START must not retrigger");
        check(!rpt_error && rpt_error_state==0,"reserved errors");
        cpu_tpu_start=0;
        repeat(4) @(negedge sys_ckg);
        fifo_empty=1;
    endtask

    // 小尺寸时有效 SA LAST 可以先于第15路输入尾巴到达。
    // 提前给出 LAST 和 EMPTY，确认 CTRL 记住 LAST，但仍等待物理输入尾巴。
    task automatic run_early_output_last;
        int before_pop, before_last, before_done;
        before_pop=pops; before_last=last_columns; before_done=dones;
        cpu_cpt_mode=1; cpu_h_size=3; cpu_w_size=3;
        start();
        for(int beat=0;beat<5;beat++) begin
            fifo_empty=0; fifo_in_rdata=make_beat(beat+200);
            fifo_in_rd_dat_last=(beat==4);
            @(posedge sys_ckg);
            check(fifo_in_re,"early LAST case must read each input");
            @(negedge sys_ckg);
        end
        fifo_empty=1; fifo_in_rd_dat_last=0;
        repeat(3) @(negedge sys_ckg);
        data_out_last=1; sa_pipeline_empty=1;
        @(negedge sys_ckg);
        data_out_last=0;
        check(last_columns==before_last,"early SA marker really precedes skew tail");
        check(dones==before_done,"early SA LAST/EMPTY must not bypass skew tail");
        repeat(25) @(negedge sys_ckg);
        check(pops-before_pop==5,"early LAST exact FIFO count");
        check(rpt_dat_in_cnt==5,"early LAST reported FIFO count");
        check(last_columns-before_last==1,"early LAST single physical tail");
        check(dones-before_done==1,"remember early output LAST until tail completion");
        check(!fifo_in_re,"early LAST held START must not retrigger");
        cpu_tpu_start=0;
        repeat(4) @(negedge sys_ckg);
    endtask

    initial begin
        reset();
        // Nonempty idle FIFO cannot trigger reads without START.
        cpu_tpu_en=1; fifo_empty=0;
        repeat(8) @(negedge sys_ckg);
        check(pops==0,"enable alone does not start");
        for(int mode=0;mode<4;mode++) begin
            run_task(16,0,mode,16);
            run_task(5,3,mode,4);
            run_task(1,0,mode,1);
        end
        run_task(31,5,1,16);
        run_early_output_last();
        // Abort with delayed tokens in flight: enable CDC must clear all lanes.
        start(); fifo_empty=0; fifo_in_rdata=make_beat(1); fifo_in_rd_dat_last=0;
        repeat(4) @(negedge sys_ckg);
        cpu_tpu_en=0; fifo_empty=1;
        repeat(20) @(negedge sys_ckg);
        check(!dat_in_vld && dat_in_a==0 && !rpt_cpt_done,"abort discards tail");
        reset();
        run_task(2,0,1,16);
        $display("CTRL_UNIT_PASS checks=%0d pops=%0d last_columns=%0d dones=%0d",checks_count,pops,last_columns,dones);
        $finish;
    end
    initial begin #200000; $fatal(1,"unit global timeout"); end
endmodule
`default_nettype wire

