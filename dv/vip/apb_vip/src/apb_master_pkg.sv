/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_master_pkg.sv
 Module/class Name             : apb_master_pkg
 Author                        : Vijay Bogati
 Description                   : APB master VIP package: transaction, config, sequencer, driver, monitor, coverage, agent, RAL adapter, sequences
***************************************************************/
`ifndef APB_MASTER_PKG_SV
`define APB_MASTER_PKG_SV

package apb_master_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_global_pkg::*;

  `include "apb_master_tx.sv"
  `include "apb_master_agent_config.sv"
  `include "apb_master_sequencer.sv"
  `include "apb_master_driver.sv"
  `include "apb_master_monitor.sv"
  `include "apb_master_coverage.sv"
  `include "apb_master_agent.sv"
  `include "apb_master_adapter.sv"
  `include "apb_master_seqs.sv"
endpackage : apb_master_pkg

`endif
