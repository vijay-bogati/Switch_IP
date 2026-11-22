/***************************************************************
 Project name                  : Switch IP
 File Name                     : hdl_top.sv
 Module/class Name             : hdl_top
 Author                        : Vijay Bogati
 Description                   : HDL top: clock, interfaces, DUT (switch_ip_top), APB protocol checker; publishes virtual interfaces to the UVM config DB
***************************************************************/
`ifndef HDL_TOP_SV
`define HDL_TOP_SV

`timescale 1ns/1ps

module hdl_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  //------------------------------------------------------------
  // Clock (100 MHz)
  //------------------------------------------------------------
  logic clk = 1'b0;
  always #5ns clk = ~clk;

  //------------------------------------------------------------
  // Interfaces
  //------------------------------------------------------------
  switch_ctrl_if ctrl_if  (.clk(clk));
  apb_if         apb_intf (.pclk(clk), .presetn(ctrl_if.rst_n));
  stream_if      src_if  [2] (.clk(clk), .rst_n(ctrl_if.rst_n));
  stream_if      dest_if [4] (.clk(clk), .rst_n(ctrl_if.rst_n));

  //------------------------------------------------------------
  // DUT
  //------------------------------------------------------------
  switch_ip_top dut (
    .clk         (clk),
    .rst_n       (ctrl_if.rst_n),

    .src1_valid  (src_if[0].valid), .src1_ready (src_if[0].ready),
    .src1_data   (src_if[0].data),  .src1_last  (src_if[0].last),
    .src2_valid  (src_if[1].valid), .src2_ready (src_if[1].ready),
    .src2_data   (src_if[1].data),  .src2_last  (src_if[1].last),

    .dest1_valid (dest_if[0].valid), .dest1_ready (dest_if[0].ready),
    .dest1_data  (dest_if[0].data),  .dest1_last  (dest_if[0].last),
    .dest2_valid (dest_if[1].valid), .dest2_ready (dest_if[1].ready),
    .dest2_data  (dest_if[1].data),  .dest2_last  (dest_if[1].last),
    .dest3_valid (dest_if[2].valid), .dest3_ready (dest_if[2].ready),
    .dest3_data  (dest_if[2].data),  .dest3_last  (dest_if[2].last),
    .dest4_valid (dest_if[3].valid), .dest4_ready (dest_if[3].ready),
    .dest4_data  (dest_if[3].data),  .dest4_last  (dest_if[3].last),

    .paddr       (apb_intf.paddr),
    .psel        (apb_intf.psel),
    .penable     (apb_intf.penable),
    .pwrite      (apb_intf.pwrite),
    .pwdata      (apb_intf.pwdata),
    .pstrb       (apb_intf.pstrb),
    .prdata      (apb_intf.prdata),
    .pready      (apb_intf.pready),
    .pslverr     (apb_intf.pslverr),

    .error       (ctrl_if.error)
  );

  //------------------------------------------------------------
  // APB protocol checker
  //------------------------------------------------------------
  apb_assertions u_apb_chk (
    .pclk    (clk),
    .presetn (ctrl_if.rst_n),
    .paddr   (apb_intf.paddr),
    .psel    (apb_intf.psel),
    .penable (apb_intf.penable),
    .pwrite  (apb_intf.pwrite),
    .pwdata  (apb_intf.pwdata),
    .pstrb   (apb_intf.pstrb),
    .prdata  (apb_intf.prdata),
    .pready  (apb_intf.pready),
    .pslverr (apb_intf.pslverr)
  );

  //------------------------------------------------------------
  // DUT assertions (switch_sva) bound into every switch_ip_top
  //------------------------------------------------------------
  bind switch_ip_top switch_sva u_switch_sva (
    .clk        (clk),
    .rst_n      (rst_sync_n),
    .rst_n_pin  (rst_n),
    .d_valid    ({dest4_valid, dest3_valid, dest2_valid, dest1_valid}),
    .d_ready    ({dest4_ready, dest3_ready, dest2_ready, dest1_ready}),
    .d_last     ({dest4_last,  dest3_last,  dest2_last,  dest1_last}),
    .src1_ready (src1_ready),
    .src2_ready (src2_ready),
    .src1_valid (src1_valid),
    .src2_valid (src2_valid),
    .error      (error),
    .p1_valid   (p1_valid),
    .p1_dest    (p1_dest),
    .p2_valid   (p2_valid),
    .p2_dest    (p2_dest),
    .g1         (g1),
    .g2         (g2)
  );

  //------------------------------------------------------------
  // Virtual interfaces to the testbench
  //------------------------------------------------------------
  initial begin
    uvm_config_db#(virtual switch_ctrl_if)::set(null, "*", "ctrl_vif", ctrl_if);
    uvm_config_db#(virtual apb_if)::set(null, "*", "apb_vif", apb_intf);
  end

  for (genvar s = 0; s < 2; s++) begin : g_src_vif
    initial uvm_config_db#(virtual stream_if)::set(null, "*", $sformatf("src_vif%0d", s), src_if[s]);
  end
  for (genvar d = 0; d < 4; d++) begin : g_dest_vif
    initial uvm_config_db#(virtual stream_if)::set(null, "*", $sformatf("dest_vif%0d", d), dest_if[d]);
  end

endmodule : hdl_top

`endif
