`timescale 1ns/1ps
`default_nettype none

module tb_ahb_slave_regmap;
    logic ahb_clk = 1'b0;
    always #5 ahb_clk = ~ahb_clk;
    logic tpu_rst_n = 1'b0;
    logic hsel = 1'b0;
    logic [2:0] hsize = 3'b010;
    logic [31:0] haddr = 32'd0;
    logic [2:0] hburst = 3'b000;
    logic [1:0] htrans = 2'b00;
    logic hwrite = 1'b0;
    logic [31:0] hwdata = 32'd0;
    logic hreadyin = 1'b1;
    logic [3:0] hprot = 4'd0;
    logic hready, hresp;
    logic [31:0] hrdata;
    logic cpu_tpu_en, cpu_sw_rst, cpu_tpu_start, cpu_tpu_crg_bypass;
    logic cpu_dat_in_b_lock, cpu_tpu_crg_en;
    logic cpu_done_clear_req;
    logic done_clear_ack = 1'b0;
    logic [3:0] cpu_h_size, cpu_w_size, cpu_dat_in_b_sel;
    logic [1:0] cpu_cpt_mode;
    logic [511:0] cpu_dat_in_b;
    logic [31:0] rpt_active_size = 32'h0010_0008;
    logic [31:0] rpt_cpt_cyc = 32'hfedc_ba98;
    logic [31:0] rpt_dat_in_cnt = 32'h7654_3210;
    logic [2:0] rpt_error_state = 3'd1;
    logic rpt_error = 1'b1;
    logic rpt_cpt_done = 1'b1;
    logic [31:0] expected [0:1023];
    integer checks = 0;
    integer transfers = 0;

    ahb_slave_regmap dut (.*);

    task automatic check32(input logic [31:0] actual,
                           input logic [31:0] wanted, input string label);
        checks = checks + 1;
        if (actual !== wanted)
            $fatal(1, "%s: got %08h expected %08h at %0t", label, actual, wanted, $time);
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
            check32(cpu_dat_in_b[i*32 +: 32], expected[9+i], $sformatf("weight %0d", i));
    endtask

    function automatic logic [31:0] expected_read(input logic [9:0] word_addr);
        case (word_addr)
            10'h001, 10'h002, 10'h008: expected_read = 32'd0;
            10'h100: expected_read = rpt_active_size;
            10'h101: expected_read = rpt_cpt_cyc;
            10'h102: expected_read = rpt_dat_in_cnt;
            10'h103: expected_read = {29'd0, rpt_error_state};
            10'h104: expected_read = {31'd0, rpt_cpt_done};
            10'h106: expected_read = {31'd0, rpt_error};
            default: expected_read = expected[word_addr];
        endcase
    endfunction

    task automatic model_write(input logic [9:0] word_addr, input logic [31:0] data);
        case (word_addr)
            10'h000, 10'h003, 10'h105: expected[word_addr] = {31'd0, data[0]};
            10'h004, 10'h005, 10'h007: expected[word_addr] = {28'd0, data[3:0]};
            10'h006: expected[word_addr] = {30'd0, data[1:0]};
            default: if ((word_addr >= 10'h009) && (word_addr <= 10'h018))
                expected[word_addr] = data;
        endcase
    endtask

    // Match the existing AHB controller: IDLE wakes, then address capture,
    // then data completion. HREADYIN is supplied by this bus environment.
    task automatic bus_transfer(input logic write_access,
                                input logic [31:0] byte_addr,
                                input logic [31:0] data,
                                input logic expect_error);
        logic [9:0] word_addr;
        word_addr = byte_addr[11:2];
        transfers = transfers + 1;
        @(negedge ahb_clk);
        hsel = 1'b1;
        htrans = 2'b10;
        haddr = byte_addr;
        hwrite = write_access;
        hwdata = data;
        @(posedge ahb_clk); // IDLE -> SAMPLE_ADDR_CTR
        @(posedge ahb_clk); // address capture -> data or first error cycle
        #1;
        check32({31'd0, hresp}, {31'd0, expect_error}, "data/error response");
        check32({31'd0, hready}, {31'd0, !expect_error}, "first response ready");
        if (expect_error) begin
            check32({30'd0, dut.regmap_wr_en, dut.regmap_rd_en}, 32'd0, "ERROR no register access");
        end else begin
            check32({22'd0, dut.regmap_addr}, {22'd0, word_addr}, "HADDR[11:2] decoded word");
            if (!write_access)
                check32(hrdata, expected_read(word_addr), $sformatf("AHB read byte %03h", byte_addr));
        end
        @(negedge ahb_clk);
        hsel = 1'b0;
        htrans = 2'b00;
        @(posedge ahb_clk); // legal write commits, or ERROR_1 -> ERROR_2
        #1;
        if (expect_error) begin
            check32({30'd0, hresp, hready}, 32'd3, "second error cycle ready+error");
            check32({30'd0, dut.regmap_wr_en, dut.regmap_rd_en}, 32'd0, "ERROR_2 no register access");
        end else if (write_access) begin
            model_write(word_addr, data);
            check32({31'd0, cpu_sw_rst}, {31'd0, ((word_addr == 10'h001) && data[0])}, "AHB soft reset W1P");
            check32({31'd0, cpu_tpu_start}, {31'd0, ((word_addr == 10'h002) && data[0])}, "AHB start W1P");
            check32({31'd0, cpu_dat_in_b_lock}, {31'd0, ((word_addr == 10'h008) && data[0])}, "AHB B lock W1P");
        end
        check_config();
        @(posedge ahb_clk);
        #1;
        check32({29'd0, cpu_sw_rst, cpu_tpu_start, cpu_dat_in_b_lock}, 32'd0, "AHB pulses clear");
        check_config();
    endtask

    task automatic word_write(input logic [9:0] word_addr, input logic [31:0] data);
        bus_transfer(1'b1, {20'd0, word_addr, 2'b00}, data, 1'b0);
    endtask

    task automatic word_read(input logic [9:0] word_addr);
        bus_transfer(1'b0, {20'd0, word_addr, 2'b00}, 32'd0, 1'b0);
    endtask

    initial begin
        for (integer i = 0; i < 1024; i = i + 1) expected[i] = 32'd0;
        expected[4] = 32'd3;
        expected[5] = 32'd3;
        repeat (2) @(posedge ahb_clk);
        #1;
        check_config();
        @(negedge ahb_clk);
        tpu_rst_n = 1'b1;
        for (integer i = 0; i <= 8; i = i + 1) word_read(10'(i));
        word_read(10'h105);

        // The new flag address must be a legal AHB read even when flag is1.
        bus_transfer(1'b0, 32'h0000_0418, 32'd0, 1'b0);

        word_write(10'h000, 32'd0);
        // Explicit byte 0x414 must reach internal word0x105, not byteindex0x105.
        bus_transfer(1'b1, 32'h0000_0414, 32'hffff_ffff, 1'b0);
        word_read(10'h000);
        word_read(10'h105);
        word_write(10'h000, 32'd1);
        word_write(10'h105, 32'd0);
        word_read(10'h000);
        word_read(10'h105);
        word_write(10'h003, 32'hffff_ffff);
        word_write(10'h004, 32'hffff_ffff);
        word_write(10'h005, 32'hffff_fffa);
        word_write(10'h006, 32'hffff_fffe);
        word_write(10'h007, 32'hffff_fff9);
        for (integer i = 3; i <= 7; i = i + 1) word_read(10'(i));
        for (integer i = 0; i < 16; i = i + 1)
            word_write(10'(9+i), 32'habcd_0000 | 32'(i));
        for (integer i = 0; i < 16; i = i + 1) word_read(10'(9+i));

        word_write(10'h001, 32'd1); word_read(10'h001);
        word_write(10'h002, 32'd1); word_read(10'h002);
        word_write(10'h008, 32'd1); word_read(10'h008);
        word_write(10'h001, 32'd0);
        word_write(10'h002, 32'd0);
        word_write(10'h008, 32'd0);
        for (integer i = 'h100; i <= 'h104; i = i + 1) begin
            word_read(10'(i));
            word_write(10'(i), 32'hffff_ffff);
            word_read(10'(i));
        end
        rpt_active_size = 32'h0004_0004;
        rpt_cpt_cyc = 32'd99;
        rpt_dat_in_cnt = 32'd77;
        rpt_error_state = 3'd0;
        rpt_error = 1'b0;
        rpt_cpt_done = 1'b0;
        for (integer i = 'h100; i <= 'h104; i = i + 1) word_read(10'(i));

        // Byte0x40C is the count, byte0x418 is the independent flag.
        // Both RO words zero-extend their inputs and ignore all0/all1 writes.
        for (integer flag = 0; flag < 2; flag = flag + 1) begin
            for (integer count = 0; count < 8; count = count + 1) begin
                rpt_error = 1'(flag);
                rpt_error_state = 3'(count);
                bus_transfer(1'b0, 32'h0000_040c, 32'd0, 1'b0);
                bus_transfer(1'b1, 32'h0000_040c, 32'hffff_ffff, 1'b0);
                bus_transfer(1'b0, 32'h0000_040c, 32'd0, 1'b0);
                bus_transfer(1'b1, 32'h0000_040c, 32'h0000_0000, 1'b0);
                bus_transfer(1'b0, 32'h0000_040c, 32'd0, 1'b0);
                bus_transfer(1'b0, 32'h0000_0418, 32'd0, 1'b0);
                bus_transfer(1'b1, 32'h0000_0418, 32'hffff_ffff, 1'b0);
                bus_transfer(1'b0, 32'h0000_0418, 32'd0, 1'b0);
                bus_transfer(1'b1, 32'h0000_0418, 32'h0000_0000, 1'b0);
                bus_transfer(1'b0, 32'h0000_0418, 32'd0, 1'b0);
            end
        end

        // Neighbor0x105 remains RW and cannot alias either error report.
        word_write(10'h105, 32'hffff_ffff);
        word_read(10'h105); word_read(10'h106); word_read(10'h103);
        word_write(10'h105, 32'h0000_0000);
        word_read(10'h105); word_read(10'h106); word_read(10'h103);

        // New upper valid boundary106;107/019/hole0ff and misalignment reject.
        bus_transfer(1'b1, 32'h0000_041c, 32'hffff_ffff, 1'b1);
        bus_transfer(1'b0, 32'h0000_041c, 32'd0, 1'b1);
        bus_transfer(1'b1, 32'h0000_0064, 32'hffff_ffff, 1'b1);
        bus_transfer(1'b1, 32'h0000_03fc, 32'hffff_ffff, 1'b1);
        bus_transfer(1'b1, 32'h0000_0415, 32'hffff_ffff, 1'b1);
        word_read(10'h105);
        word_read(10'h000);
        $display("PASS tb_ahb_slave_regmap: %0d checks, %0d transfers", checks, transfers);
        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "tb_ahb_slave_regmap timeout");
    end
endmodule

`default_nettype wire
