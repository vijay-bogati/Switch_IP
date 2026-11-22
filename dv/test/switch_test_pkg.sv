/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_test_pkg.sv
 Module/class Name             : switch_test_pkg
 Author                        : Vijay Bogati
 Description                   : Test package: base test and test library
***************************************************************/
`ifndef SWITCH_TEST_PKG_SV
`define SWITCH_TEST_PKG_SV

package switch_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_global_pkg::*;
  import apb_master_pkg::*;
  import stream_pkg::*;
  import switch_ral_pkg::*;
  import switch_env_pkg::*;
  import switch_vseq_pkg::*;

  `include "switch_base_test.sv"
  `include "switch_tests.sv"
endpackage : switch_test_pkg

`endif
