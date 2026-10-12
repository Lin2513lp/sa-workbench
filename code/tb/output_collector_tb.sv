`timescale 1ns/1ps
`default_nettype none
// Independent original-vector timestamps and mock PE data; no CTRL dependency.
module output_collector_tb;
    logic sys_ckg=0, tpu_rst_n=0, stream_enable=0;
    always #1.25 sys_ckg=~sys_ckg;
    logic [3:0] active_h_size=0,active_w_size=0;
    logic [1:0] cpt_mode=0;
    logic vector_in_vld=0,vector_in_last=0;
    logic [511:0] raw_dat_in=0,dat_out;
    logic [15:0] raw_dat_in_vld=0;
    logic dat_out_vld,dat_out_last;
    int checks=0,jobs=0,results=0,valid_zeros=0;
    output_collector dut(.*);
`ifdef FSDB_TRACE
    string fsdb_file_runtime;
    initial begin
        if(!$value$plusargs("FSDB_FILE=%s",fsdb_file_runtime))
            fsdb_file_runtime="waves/output_collector_tb.fsdb";
        $fsdbDumpfile(fsdb_file_runtime);
        $fsdbDumpvars(0,output_collector_tb,"+all");
    end
`endif
`ifdef VERILATOR_TRACE
    initial begin
        $dumpfile("build/verilator/waves/output_collector_tb.vcd");
        $dumpvars(0,output_collector_tb);
    end
`endif
    task automatic check(input logic condition,input string reason);
        checks++;
        if(!condition) $fatal(1,"output_collector_tb: %s",reason);
    endtask
    function automatic logic [31:0] word(input int k,input int col);
        word=(k%4==0 || k==15)?0:32'(1000+k*31+col);
    endfunction
    task automatic sample_cycle;
        @(posedge sys_ckg);#0.1;
    endtask
    task automatic run_stream(input int mode,input int n,input int gap);
        int latency,spacing,last_pop,source_t,k,last_count;
        logic [511:0] expected_bus,gated_bus;
        logic [15:0] mask,gated_mask;
        logic expected_last;
        latency=(mode==2)?7:((mode==3)?4:1);
        spacing=gap+1;last_pop=15*spacing;last_count=0;jobs++;
        @(negedge sys_ckg);
        stream_enable=1;active_h_size=4'(n-1);active_w_size=4'(n-1);
        cpt_mode=2'(mode);
        for(int t=0;t<=last_pop+2*(n-1)+(latency-1)+5;t++) begin
            if(t!=0) @(negedge sys_ckg);
            vector_in_vld=t<=last_pop && t%spacing==0;
            vector_in_last=vector_in_vld && t==last_pop;
            sample_cycle();
            raw_dat_in_vld='1; // Deliberately includes partial/padding valids.
            expected_bus=0;mask=0;expected_last=0;
            for(int col=0;col<16;col++) begin
                raw_dat_in[col*32+:32]=32'hdead0000+32'(t*16+col);
                source_t=t-(n-1)-col-(latency-1);
                if(col<n && source_t>=0 && source_t<=last_pop && source_t%spacing==0) begin
                    k=source_t/spacing;
                    raw_dat_in[col*32+:32]=word(k,col);
                    expected_bus[col*32+:32]=word(k,col);
                    mask[col]=1;
                    expected_last|=k==15 && col==n-1;
                    results++;if(word(k,col)==0)valid_zeros++;
                end
            end
            #0.1;
            check(dat_out===expected_bus,$sformatf("bus mode%0d N%0d gap%0d T%0d",mode,n,gap,t));
            check(dat_out_vld===(|mask),"exact valid including input bubbles");
            check(dat_out_last===expected_last,"exact LAST including final valid-zero word");
            if(dat_out_last)last_count++;
            // Suppress each raw-valid lane within this cycle; verify full bus,
            // beat valid and LAST, then restore before the next clock edge.
            if(|mask) begin
                for(int col=0;col<16;col++) if(mask[col]) begin
                    gated_bus=expected_bus;gated_bus[col*32+:32]=0;
                    gated_mask=mask;gated_mask[col]=0;
                    raw_dat_in_vld[col]=0;#0.001;
                    check(dat_out===gated_bus,"raw-invalid lane must be zero");
                    check(dat_out_vld===(|gated_mask),"raw-invalid valid suppression");
                    check(dat_out_last===(expected_last && col!=n-1),"raw-invalid LAST suppression");
                    raw_dat_in_vld[col]=1;#0.001;
                end
            end
        end
        check(last_count==1,"one LAST per job");
    endtask
    initial begin
        repeat(2)sample_cycle();
        @(negedge sys_ckg);tpu_rst_n=1;
        for(int mode=0;mode<4;mode++)
            for(int size_bin=0;size_bin<3;size_bin++)
                for(int gap_bin=0;gap_bin<3;gap_bin++)
                    run_stream(mode,(size_bin==0)?1:((size_bin==1)?4:16),
                        (gap_bin==0)?0:((gap_bin==1)?3:20));
        // Abort an in-flight FP16 N16 task; disable clears both histories.
        @(negedge sys_ckg);
        cpt_mode=2;active_h_size=15;active_w_size=15;
        vector_in_vld=1;vector_in_last=1;stream_enable=1;
        sample_cycle();
        @(negedge sys_ckg);
        vector_in_vld=0;vector_in_last=0;stream_enable=0;
        sample_cycle();
        check(dat_out===0 && !dat_out_vld && !dat_out_last,"disable clears in-flight task");
        @(negedge sys_ckg);stream_enable=1;active_h_size=0;active_w_size=0;
        for(int t=0;t<40;t++) begin
            sample_cycle();
            check(dat_out===0 && !dat_out_vld && !dat_out_last,"no stale tokens after disable/config change");
        end
        $display("output_collector_tb: PASS jobs=%0d results=%0d valid_zeros=%0d checks=%0d",jobs,results,valid_zeros,checks);
        $finish;
    end
    initial begin #1000000;$fatal(1,"output_collector_tb: timeout");end
endmodule
`default_nettype wire
