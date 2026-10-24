`timescale 1ns/1ps
`default_nettype none
// Independent source timestamps; mock PE results include misleading padding.
module output_collector_tb;
    logic sys_ckg=0, tpu_rst_n=0, stream_enable=0;
    always #1.25 sys_ckg=~sys_ckg;
    logic [3:0] active_h_size=0, active_w_size=0;
    logic [1:0] cpt_mode=0;
    logic dat_in_vld=0, dat_in_last=0;
    logic [511:0] raw_dat_in=0, dat_out;
    logic [15:0] raw_dat_in_vld=0;
    logic dat_out_vld, dat_out_last, collector_empty;
    int checks=0, jobs=0, results=0, valid_zeros=0;
    output_collector dut(.*);
    task automatic check(input logic condition, input string reason);
        checks++;
        if (!condition) $fatal(1,"output_collector_tb: %s",reason);
    endtask
    function automatic logic [31:0] word(input int k, input int col, input int count);
        word=(k%4==0 || k==count-1)?0:32'(1000+k*31+col);
    endfunction
    task automatic sample_cycle;
        @(posedge sys_ckg); #0.1;
    endtask
    task automatic run_stream(input int mode, input int n, input int count);
        int latency, source_t, k, last_count;
        logic [511:0] expected_bus;
        logic [15:0] mask;
        logic expected_last;
        latency=(mode==2)?7:((mode==3)?4:1);
        last_count=0; jobs++;
        @(negedge sys_ckg);
        stream_enable=1; active_h_size=4'(n-1); active_w_size=4'(n-1);
        cpt_mode=2'(mode);
        for(int t=0; t<=count-1+15+2*(n-1)+(latency-1)+5; t++) begin
            if(t!=0) @(negedge sys_ckg);
            dat_in_vld=t<=count-1+15;
            dat_in_last=t==count-1+15;
            sample_cycle();
            raw_dat_in_vld='1;
            expected_bus=0; mask=0; expected_last=0;
            for(int col=0; col<16; col++) begin
                raw_dat_in[col*32+:32]=32'hdead0000+32'(t*16+col);
                source_t=t-(n-1)-col-(latency-1);
                if(col<n && source_t>=0 && source_t<count) begin
                    raw_dat_in[col*32+:32]=word(source_t,col,count);
                    // An invalid intermediate raw result must stay suppressed
                    // after buffering. Keep the final result valid for LAST.
                    if(source_t==1 && col==0 && count>2) raw_dat_in_vld[col]=0;
                end
                source_t=t-15-(n-1)-col-(latency-1);
                if(col<n && source_t>=0 && source_t<count &&
                    !(source_t==1 && col==0 && count>2)) begin
                    k=source_t;
                    expected_bus[col*32+:32]=word(k,col,count);
                    mask[col]=1;
                    expected_last|=k==count-1 && col==n-1;
                    results++; if(word(k,col,count)==0) valid_zeros++;
                end
            end
            #0.1;
            check(dat_out===expected_bus,$sformatf("bus mode%0d N%0d length%0d T%0d",mode,n,count,t));
            check(dat_out_vld===(|mask),"exact valid including startup/padding");
            check(dat_out_last===expected_last,"one LAST on final valid zero result");
            if(dat_out_last) last_count++;
        end
        check(last_count==1,"one LAST per job");
        check(collector_empty,"pending results drained");
    endtask
    initial begin
        repeat(2)sample_cycle();
        @(negedge sys_ckg); tpu_rst_n=1;
        for(int mode=0; mode<4; mode++)
            for(int size_bin=0; size_bin<3; size_bin++)
                for(int length_bin=0; length_bin<6; length_bin++)
                    run_stream(mode,(size_bin==0)?1:((size_bin==1)?4:16),
                        (length_bin==0)?1:((length_bin==1)?2:((length_bin==2)?4:
                        ((length_bin==3)?16:((length_bin==4)?31:64)))));
        // Abort while metadata and result buffers still contain pending work.
        @(negedge sys_ckg);
        cpt_mode=2; active_h_size=15; active_w_size=15;
        dat_in_vld=1; dat_in_last=0; stream_enable=1;
        repeat(20) sample_cycle();
        @(negedge sys_ckg);
        dat_in_vld=0; dat_in_last=0; stream_enable=0;
        sample_cycle();
        check(dat_out===0 && !dat_out_vld && !dat_out_last && collector_empty,
            "disable clears pending metadata and data");
        @(negedge sys_ckg); stream_enable=1; active_h_size=0; active_w_size=0;
        for(int t=0; t<60; t++) begin
            sample_cycle();
            check(dat_out===0 && !dat_out_vld && !dat_out_last && collector_empty,
                "no stale results after disable/config change");
        end
        $display("output_collector_tb: PASS jobs=%0d results=%0d valid_zeros=%0d checks=%0d",jobs,results,valid_zeros,checks);
        $finish;
    end
    initial begin #1000000; $fatal(1,"output_collector_tb: timeout"); end
endmodule
`default_nettype wire
