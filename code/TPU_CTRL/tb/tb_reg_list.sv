`timescale 1ns/1ps
`default_nettype none

module tb_reg_list;
    logic hclk = 1'b0;
    always #5 hclk = ~hclk;
    logic hrstn = 1'b0;
    logic [9:0] ahb_addr = 10'h000;
    logic [31:0] ahb_wr_data = 32'd0;
    logic ahb_wr_en = 1'b0;
    logic ahb_rd_en = 1'b0;
    logic [31:0] ahb_rd_data;
    logic cpu_tpu_en, cpu_sw_rst, cpu_tpu_start, cpu_tpu_crg_bypass;
    logic cpu_dat_in_b_lock, cpu_tpu_crg_en;
    logic cpu_done_clear_req;
    logic done_clear_ack = 1'b0;
    logic [3:0] cpu_h_size, cpu_w_size, cpu_dat_in_b_sel;
    logic [1:0] cpu_cpt_mode;
    logic [511:0] cpu_dat_in_b;
    logic [31:0] rpt_active_size = 32'd0;
    logic [31:0] rpt_cpt_cyc = 32'd0;
    logic [31:0] rpt_dat_in_cnt = 32'd0;
    logic [2:0] rpt_error_state = 3'd0;
    logic rpt_error = 1'b0;
    logic rpt_cpt_done = 1'b0;
    logic [31:0] expected [0:1023];
    integer checks = 0;

    reg_list dut (.*);

    task automatic check32(input logic [31:0] actual,
                           input logic [31:0] wanted, input string label);
        checks = checks + 1;
        if (actual !== wanted) begin
            $fatal(1, "%s: got %08h expected %08h at %0t", label, actual, wanted, $time);
        end
    endtask

    task automatic reset_expected;
        for (integer i = 0; i < 1024; i = i + 1) expected[i] = 32'd0;
        expected[4] = 32'd3;
        expected[5] = 32'd3;
    endtask

    task automatic check_config;
        check32({31'd0, cpu_tpu_en}, expected[0], "en output");
        check32({31'd0, cpu_tpu_crg_bypass}, expected[3], "bypass output");
        check32({28'd0, cpu_h_size}, expected[4], "H output");
        check32({28'd0, cpu_w_size}, expected[5], "W output");
        check32({30'd0, cpu_cpt_mode}, expected[6], "mode output");
        check32({28'd0, cpu_dat_in_b_sel}, expected[7], "B select output");
        check32({31'd0, cpu_tpu_crg_en}, expected['h105], "CRG enable output");
        for (integer i = 0; i < 16; i = i + 1)
            check32(cpu_dat_in_b[i*32 +: 32], expected[9+i], $sformatf("weight lane %0d", i));
    endtask

    function automatic logic [31:0] expected_read(input logic [9:0] address);
        case (address)
            10'h000, 10'h003, 10'h004, 10'h005, 10'h006, 10'h007,
            10'h009, 10'h00a, 10'h00b, 10'h00c, 10'h00d, 10'h00e,
            10'h00f, 10'h010, 10'h011, 10'h012, 10'h013, 10'h014,
            10'h015, 10'h016, 10'h017, 10'h018, 10'h105:
                expected_read = expected[address];
            10'h100: expected_read = rpt_active_size;
            10'h101: expected_read = rpt_cpt_cyc;
            10'h102: expected_read = rpt_dat_in_cnt;
            10'h103: expected_read = {29'd0, rpt_error_state};
            10'h104: expected_read = {31'd0, rpt_cpt_done};
            10'h106: expected_read = {31'd0, rpt_error};
            default: expected_read = 32'd0;
        endcase
    endfunction

    task automatic read_check(input logic [9:0] address);
        @(negedge hclk);
        ahb_addr = address;
        ahb_rd_en = 1'b1;
        #1;
        check32(ahb_rd_data, expected_read(address), $sformatf("read word %03h", address));
        ahb_rd_en = 1'b0;
        #1;
        check32(ahb_rd_data, 32'd0, "read disabled returns zero");
    endtask

    task automatic write_check(input logic [9:0] address, input logic [31:0] data);
        @(negedge hclk);
        ahb_addr = address;
        ahb_wr_data = data;
        ahb_wr_en = 1'b1;
        case (address)
            10'h000, 10'h003, 10'h105: expected[address] = {31'd0, data[0]};
            10'h004, 10'h005, 10'h007: expected[address] = {28'd0, data[3:0]};
            10'h006: expected[address] = {30'd0, data[1:0]};
            default: if ((address >= 10'h009) && (address <= 10'h018))
                expected[address] = data;
        endcase
        @(posedge hclk);
        #1;
        check_config();
        check32({31'd0, cpu_sw_rst}, {31'd0, ((address == 10'h001) && data[0])}, "SW reset pulse");
        check32({31'd0, cpu_tpu_start}, {31'd0, ((address == 10'h002) && data[0])}, "start pulse");
        check32({31'd0, cpu_dat_in_b_lock}, {31'd0, ((address == 10'h008) && data[0])}, "B lock pulse");
        ahb_rd_en = 1'b1;
        #1;
        check32(ahb_rd_data, expected_read(address), "read during write/pulse");
        @(negedge hclk);
        ahb_wr_en = 1'b0;
        ahb_rd_en = 1'b0;
        @(posedge hclk);
        #1;
        check32({29'd0, cpu_sw_rst, cpu_tpu_start, cpu_dat_in_b_lock}, 32'd0, "pulses clear next cycle");
        check_config();
    endtask

    task automatic apply_reset;
        @(negedge hclk);
        #2;
        hrstn = 1'b0;
        ahb_wr_en = 1'b0;
        ahb_rd_en = 1'b0;
        reset_expected();
        #1;
        check_config();
        check32({29'd0, cpu_sw_rst, cpu_tpu_start, cpu_dat_in_b_lock}, 32'd0, "reset clears pulses");
        repeat (2) @(posedge hclk);
        @(negedge hclk);
        hrstn = 1'b1;
    endtask

    initial begin
        reset_expected();
        repeat (2) @(posedge hclk);
        #1;
        check_config();
        @(negedge hclk);
        hrstn = 1'b1;
        for (integer i = 0; i <= 24; i = i + 1) read_check(10'(i));
        for (integer i = 'h100; i <= 'h106; i = i + 1) read_check(10'(i));

        // All narrow field values; unused high bits must never be stored/read back.
        write_check(10'h000, 32'hffff_fffe);
        write_check(10'h000, 32'hffff_ffff);
        write_check(10'h003, 32'hffff_fffe);
        write_check(10'h003, 32'hffff_ffff);
        for (integer i = 0; i < 16; i = i + 1) begin
            write_check(10'h004, 32'hffff_fff0 | 32'(i));
            write_check(10'h005, 32'hffff_fff0 | 32'(15-i));
            write_check(10'h007, 32'hffff_fff0 | 32'(i));
        end
        for (integer i = 0; i < 4; i = i + 1)
            write_check(10'h006, 32'hffff_fffc | 32'(i));

        // Weight word i maps only to slice i, not to adjacent slices or controls.
        for (integer i = 0; i < 16; i = i + 1)
            write_check(10'(9+i), 32'h1234_0000 | 32'(i));
        for (integer i = 0; i < 16; i = i + 1) read_check(10'(9+i));
        for (integer i = 15; i >= 0; i = i - 1)
            write_check(10'(9+i), 32'hfedc_0000 | 32'(i));

        // Independent enable registers, including writes containing reserved bits.
        write_check(10'h000, 32'd0);
        write_check(10'h105, 32'hffff_ffff);
        read_check(10'h000);
        read_check(10'h105);
        write_check(10'h000, 32'd1);
        write_check(10'h105, 32'hffff_fffe);
        read_check(10'h000);
        read_check(10'h105);

        write_check(10'h001, 32'hffff_fffe);
        write_check(10'h001, 32'hffff_ffff);
        write_check(10'h002, 32'hffff_fffe);
        write_check(10'h002, 32'hffff_ffff);
        write_check(10'h008, 32'hffff_fffe);
        write_check(10'h008, 32'hffff_ffff);

        // Report values are supplied coherently in hclk by caller; DONE also accepts W1C.
        rpt_active_size = 32'h0010_000f;
        rpt_cpt_cyc = 32'h1234_5678;
        rpt_dat_in_cnt = 32'h8765_4321;
        rpt_error_state = 3'd1;
        rpt_cpt_done = 1'b1;
        for (integer i = 'h100; i <= 'h104; i = i + 1) begin
            read_check(10'(i));
            write_check(10'(i), 32'hffff_ffff);
            read_check(10'(i));
        end
        rpt_active_size = 32'h0004_0003;
        rpt_cpt_cyc = 32'hffff_fffe;
        rpt_dat_in_cnt = 32'h8000_0001;
        rpt_error_state = 3'd0;
        rpt_cpt_done = 1'b0;
        for (integer i = 'h100; i <= 'h104; i = i + 1) read_check(10'(i));

        // Separate live RO words: count0x103, flag0x106; no packed bit3.
        // All16 independent pairs, zero extension and both RO write patterns.
        for (integer flag = 0; flag < 2; flag = flag + 1) begin
            for (integer count = 0; count < 8; count = count + 1) begin
                rpt_error = 1'(flag);
                rpt_error_state = 3'(count);
                read_check(10'h103);
                write_check(10'h103, 32'hffff_ffff);
                read_check(10'h103);
                write_check(10'h103, 32'h0000_0000);
                read_check(10'h103);
                read_check(10'h106);
                write_check(10'h106, 32'hffff_ffff);
                read_check(10'h106);
                write_check(10'h106, 32'h0000_0000);
                read_check(10'h106);
            end
        end

        // Neighbor0x105 remains RW; toggling it cannot change either report.
        write_check(10'h105, 32'hffff_ffff);
        read_check(10'h105); read_check(10'h106); read_check(10'h103);
        write_check(10'h105, 32'h0000_0000);
        read_check(10'h105); read_check(10'h106); read_check(10'h103);

        write_check(10'h019, 32'hffff_ffff); read_check(10'h019);
        write_check(10'h0ff, 32'hffff_ffff); read_check(10'h0ff);
        write_check(10'h107, 32'hffff_ffff); read_check(10'h107);
        write_check(10'h3ff, 32'hffff_ffff); read_check(10'h3ff);
        apply_reset();
        $display("PASS tb_reg_list: %0d checks", checks);
        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "tb_reg_list timeout");
    end
endmodule

`default_nettype wire
