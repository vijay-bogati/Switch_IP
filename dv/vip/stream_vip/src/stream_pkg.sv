/***************************************************************
 Project name                  : Switch IP
 File Name                     : stream_pkg.sv
 Module/class Name             : stream_pkg
 Author                        : Vijay Bogati
 Description                   : Stream VIP package: packet/beat items, config, sequencer, source/sink drivers, monitor, agent, sequences
***************************************************************/
`ifndef STREAM_PKG_SV
`define STREAM_PKG_SV

package stream_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "stream_tx.sv"
  `include "stream_beat.sv"
  `include "stream_agent_config.sv"
  `include "stream_sequencer.sv"
  `include "stream_src_driver.sv"
  `include "stream_sink_driver.sv"
  `include "stream_monitor.sv"
  `include "stream_agent.sv"
  `include "stream_seqs.sv"
endpackage : stream_pkg

`endif
