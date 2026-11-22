/***************************************************************
 Project name                  : Switch IP
 File Name                     : hvl_top.sv
 Module/class Name             : hvl_top
 Author                        : Vijay Bogati
 Description                   : HVL top: starts the UVM test selected with +UVM_TESTNAME
***************************************************************/
`ifndef HVL_TOP_SV
`define HVL_TOP_SV

`timescale 1ns/1ps

module hvl_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import switch_test_pkg::*;

  initial run_test("switch_base_test");
endmodule : hvl_top

`endif
