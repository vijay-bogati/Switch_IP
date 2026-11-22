/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_env_pkg.sv
 Module/class Name             : switch_env_pkg
 Author                        : Vijay Bogati
 Description                   : Environment package: types, env config, coverage, scoreboard, virtual sequencer, env
***************************************************************/
`ifndef SWITCH_ENV_PKG_SV
`define SWITCH_ENV_PKG_SV

package switch_env_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_global_pkg::*;
  import apb_master_pkg::*;
  import stream_pkg::*;
  import switch_ral_pkg::*;

  `include "switch_env_types.sv"
  `include "switch_env_config.sv"
  `include "switch_coverage.sv"
  `include "switch_scoreboard.sv"
  `include "switch_virtual_sequencer.sv"
  `include "switch_env.sv"
endpackage : switch_env_pkg

`endif
