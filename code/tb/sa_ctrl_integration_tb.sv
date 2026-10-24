`timescale 1ns/1ps
`default_nettype none
module sa_ctrl_integration_tb;
    logic sys_ckg=0;
    always #1.25 sys_ckg=!sys_ckg;
    wire [63:0] pe_ckg={64{sys_ckg}};
    logic tpu_rst_n=0, cpu_tpu_en=0, cpu_tpu_start=0;
    logic [1:0] cpu_cpt_mode=1;
    logic [3:0] cpu_h_size=15, cpu_w_size=15;
    logic cpu_dat_in_b_lock=0;
    logic [511:0] cpu_dat_in_b=0;
    logic [3:0] cpu_dat_in_b_sel=0;
    logic fifo_in_we=0, rd_dat_last=0;
    logic [511:0] fifo_in_wdata=0;
    logic fifo_in_pre_full;
    logic [511:0] dat_out;
    logic dat_out_vld, dat_out_last;
    logic [31:0] rpt_active_size,rpt_dat_in_cnt;
    logic rpt_cpt_done,rpt_error;
    logic cpu_done_clear_req=1'b0;
    logic done_clear_ack;
    logic done_prev=1'b0;
    logic [2:0] rpt_error_state;
    tpu_compute_path #(.FIFO_DEPTH(128)) dut(.*);

    int cycle=0, case_no=0, active_size=16, active_width=16, mode=1, latency=1;
    int total_checks=0,total_raw_checks=0,total_raw_mismatches=0;
    int raw_checks=0,raw_mismatches=0,final_snapshot_mismatches=0;
    int output_beats=0,done_pulses=0,pop_count=0,tail_count=0;
    int pop_cycle[0:63];
    int packet_length=16, output_results=0;
    logic [511:0] expected_bus;
    logic expected_output_valid, expected_output_last;
    logic [511:0] history_data[0:14];
    logic history_valid[0:14],history_last[0:14];
    logic [31:0] expect_word;
    logic expect_valid;
    logic check_case=0,trace_case=0;
    int trace_fd,summary_fd;
    logic pop_at_edge,tail_at_edge,sa_last_at_edge;

    task automatic check(input logic ok,input string reason);
        total_checks++;
        if(!ok) $fatal(1,"INTEGRATION case%0d %s",case_no,reason);
    endtask
    function automatic int aval(input int beat,input int row);
        if(beat%4==0 || beat==packet_length-1) aval=0;
        else if(mode<2) aval=((beat*3+row*5+1)%13)-6;
        else aval=1+(beat+row*2)%4;
    endfunction
    function automatic int bval(input int row,input int col);
        if(mode<2) bval=((row*5+col*3)%7)-3;
        else bval=1+(row*3+col)%4;
    endfunction
    function automatic logic [31:0] as_fp32(input int value);
        int msb;
        logic [31:0] normalized;
        if(value==0) as_fp32=0;
        else begin
            msb=0;
            for(int i=0;i<31;i++) if((value>>i)&1) msb=i;
            normalized=32'(value)<<(23-msb);
            as_fp32={1'b0,8'(127+msb),normalized[22:0]};
        end
    endfunction
    function automatic logic [31:0] operand(input int value);
        if(mode<2) operand=32'(value);
        else if(mode==3) operand=as_fp32(value);
        else begin
            case(value)
                1:operand=32'h3c00;
                2:operand=32'h4000;
                3:operand=32'h4200;
                4:operand=32'h4400;
                default:operand=0;
            endcase
        end
    endfunction
    function automatic logic [511:0] make_beat(input int beat);
        for(int row=0;row<16;row++) make_beat[row*32+:32]=operand(aval(beat,row));
    endfunction
    // Arithmetic oracle derives each result from the original unskewed
    // source matrix and stationary B. It does not inspect PE intermediate data.
    function automatic logic [31:0] expected_result(input int beat,input int col);
        int sum;
        sum=0;
        for(int row=0;row<active_size;row++) sum+=aval(beat,row)*bval(row,col);
        expected_result=(mode<2)?32'(sum):as_fp32(sum);
    endfunction

    always @(posedge sys_ckg) begin
        cycle++;
        pop_at_edge=dut.fifo_in_re;
        tail_at_edge=dut.dat_in_last;
        sa_last_at_edge=dat_out_vld && dat_out_last;
        if(!tpu_rst_n || !dut.cpu_tpu_en_sync) begin
            for(int j=0;j<15;j++) begin
                history_data[j]=0;history_valid[j]=0;history_last[j]=0;
            end
        end
        if(check_case) begin
            expect_valid=pop_at_edge;
            for(int row=0;row<16;row++) begin
                if(row==0) expect_word=pop_at_edge?dut.fifo_in_rdata[0+:32]:0;
                else begin
                    expect_word=history_valid[row-1]?history_data[row-1][row*32+:32]:0;
                    expect_valid |= history_valid[row-1];
                end
                check(dut.dat_in_a[row*32+:32]===expect_word,$sformatf("CTRL skew lane%0d",row));
            end
            check(dut.dat_in_vld===expect_valid,"CTRL shared valid");
            check(dut.dat_in_last===history_last[14],"CTRL physical last");
            if(pop_at_edge) begin
                check(pop_count<packet_length,"extra FIFO pop");
                check(dut.fifo_in_rdata===make_beat(pop_count),"FIFO word order/data");
                check(dut.fifo_in_rd_dat_last== (pop_count==packet_length-1),"FIFO LAST association");
                if(pop_count>0) check(cycle==pop_cycle[pop_count-1]+1,"source FIFO packet is contiguous");
                pop_cycle[pop_count]=cycle;
                pop_count++;
            end
            if(tail_at_edge) tail_count++;

        end
        for(int j=14;j>0;j--) begin
            history_data[j]=history_data[j-1];history_valid[j]=history_valid[j-1];history_last[j]=history_last[j-1];
        end
        history_data[0]=pop_at_edge?dut.fifo_in_rdata:0;
        history_valid[0]=pop_at_edge;
        history_last[0]=pop_at_edge && dut.fifo_in_rd_dat_last;
        #0.1;
        if(check_case) begin
            check(rpt_dat_in_cnt==32'(pop_count),"CTRL input counter");
            if(rpt_cpt_done && !done_prev) begin
                done_pulses++;
                check(sa_last_at_edge,"DONE follows actual SA final output");
                check(tail_count==1,"DONE must follow skew tail");
            end
            for(int k=0;k<pop_count;k++) begin
                for(int col=0;col<active_width;col++) begin
                    if(cycle==pop_cycle[k]+active_size-1+col+latency-1) begin
                        raw_checks++;total_raw_checks++;
                        if(!dut.u_sa.raw_dat_out_vld[col] || dut.u_sa.raw_dat_out[col*32+:32]!==expected_result(k,col)) begin
                            raw_mismatches++;total_raw_mismatches++;
                            if(raw_mismatches<=4) $display("RAW_MISMATCH case=%0d mode=%0d H=%0d beat=%0d col=%0d expected=%h actual=%h valid=%b",case_no,mode,active_size,k,col,expected_result(k,col),dut.u_sa.raw_dat_out[col*32+:32],dut.u_sa.raw_dat_out_vld[col]);
                        end
                    end
                end
            end
            expected_bus=0; expected_output_valid=0; expected_output_last=0;
            for(int k=0;k<pop_count;k++) begin
                for(int col=0;col<active_width;col++) begin
                    if(cycle==pop_cycle[k]+15+active_size-1+col+latency-1) begin
                        expected_bus[col*32+:32]=expected_result(k,col);
                        expected_output_valid=1;
                        expected_output_last|=k==packet_length-1 && col==active_width-1;
                        output_results++;
                    end
                end
            end
            check(dat_out===expected_bus,"all512 output bits match independent source-matrix oracle");
            check(dat_out_vld===expected_output_valid,"exact delayed output valid");
            check(dat_out_last===expected_output_last,"exact final output LAST");
            if(dat_out_vld) output_beats++;

        end
        done_prev = rpt_cpt_done;
    end

    task automatic tick(input int n);
        repeat(n) @(negedge sys_ckg);
    endtask
    task automatic run_case(input int m,input int size,input int count);
        case_no++;packet_length=count;output_results=0;mode=m;active_size=size;active_width=size;
        latency=(m==2)?7:((m==3)?4:1);
        check_case=0;cpu_tpu_start=0;cpu_tpu_en=0;fifo_in_we=0;cpu_dat_in_b_lock=0;
        tpu_rst_n=0;tick(3);tpu_rst_n=1;tick(3);
        cpu_cpt_mode=2'(m);cpu_h_size=4'(size-1);cpu_w_size=4'(active_width-1);
        cpu_tpu_en=1;tick(5);
        for(int row=0;row<16;row++) begin
            cpu_dat_in_b_sel=4'(row);
            for(int col=0;col<16;col++) cpu_dat_in_b[col*32+:32]=operand(bval(row,col));
            cpu_dat_in_b_lock=1;tick(4);cpu_dat_in_b_lock=0;tick(4);
        end
        pop_count=0;raw_checks=0;raw_mismatches=0;final_snapshot_mismatches=0;
        output_beats=0;done_pulses=0;tail_count=0;
        trace_case=(case_no==1);
        // Preload the complete variable-length contiguous source packet.
        begin
            for(int k=0;k<packet_length;k++) begin
                fifo_in_we=1;fifo_in_wdata=make_beat(k);rd_dat_last=(k==packet_length-1);tick(1);
            end
            fifo_in_we=0;rd_dat_last=0;
        end
        check_case=1;cpu_tpu_start=1;tick(4);cpu_tpu_start=0;
        for(int timeout=0;timeout<200 && done_pulses==0;timeout++) tick(1);
        tick(3);
        check(pop_count==packet_length,"all16 original FIFO vectors consumed");
        check(tail_count==1,"exactly one physical input tail");
        check(done_pulses==1,"exactly one computation completion");
        check(output_beats==packet_length+active_width-1,"SA wavefront beat count");
        check(output_results==packet_length*active_width,"all matrix results checked");
        check(raw_checks==packet_length*active_width,"checked every mathematical output element at raw boundary");
        check(!rpt_error && rpt_error_state==0,"legal task has no protocol errors");
        check(rpt_active_size=={16'(size),16'(active_width)},"SA active size report");
        $display("CASE_RESULT case=%0d mode=%0d H=%0d W=%0d length=%0d ctrl=PASS raw_checks=%0d raw_mismatches=%0d output_beats=%0d final_snapshot_mismatches=%0d",case_no,m,size,active_width,count,raw_checks,raw_mismatches,output_beats,final_snapshot_mismatches);
        check_case=0;trace_case=0;
    endtask

    initial begin
        for(int m=0;m<4;m++) begin
            for(int sb=0;sb<3;sb++) begin
                for(int lb=0;lb<5;lb++) begin
                    run_case(m,(sb==0)?1:((sb==1)?4:16),
                        (lb==0)?1:((lb==1)?2:((lb==2)?4:((lb==3)?16:64))));
                end
            end
        end
        $display("SA_CTRL_ORIGINAL_INTERFACE_PASS cases=%0d protocol_checks=%0d",case_no,total_checks);
        if(total_raw_mismatches==0) $display("ARRAY_ARITHMETIC_PASS raw_checks=%0d raw_mismatches=0; complete buffered collector outputs also checked",total_raw_checks);
        else $display("ARRAY_ARITHMETIC_FAIL raw_checks=%0d raw_mismatches=%0d",total_raw_checks,total_raw_mismatches);
        $display("sa_ctrl_integration_tb: PASS");
        $finish;
    end
    initial begin #1000000; $fatal(1,"integration global timeout"); end
endmodule
`default_nettype wire

