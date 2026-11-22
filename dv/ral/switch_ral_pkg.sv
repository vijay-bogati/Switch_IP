/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_ral_pkg.sv
 Module/class Name             : switch_ral_pkg
 Author                        : Vijay Bogati
 Description                   : Package wrapping the Switch IP RAL model
***************************************************************/
`ifndef SWITCH_RAL_PKG_SV
`define SWITCH_RAL_PKG_SV

package switch_ral_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "switch_reg_block.sv"
endpackage : switch_ral_pkg

`endif
