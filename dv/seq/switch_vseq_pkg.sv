/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_vseq_pkg.sv
 Module/class Name             : switch_vseq_pkg
 Author                        : Vijay Bogati
 Description                   : Virtual sequence package
***************************************************************/
`ifndef SWITCH_VSEQ_PKG_SV
`define SWITCH_VSEQ_PKG_SV

package switch_vseq_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_global_pkg::*;
  import apb_master_pkg::*;
  import stream_pkg::*;
  import switch_ral_pkg::*;
  import switch_env_pkg::*;

  `include "switch_base_vseq.sv"
  `include "switch_reg_vseqs.sv"
  `include "switch_traffic_vseqs.sv"
  `include "switch_system_vseqs.sv"
endpackage : switch_vseq_pkg

`endif
