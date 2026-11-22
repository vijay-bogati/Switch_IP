/***************************************************************
 Project name                  : Switch IP
 File Name                     : stream_sequencer.sv
 Module/class Name             : stream_sequencer
 Author                        : Vijay Bogati
 Description                   : Sequencer for stream source agents (packet level items)
***************************************************************/
`ifndef STREAM_SEQUENCER_SV
`define STREAM_SEQUENCER_SV

class stream_sequencer extends uvm_sequencer #(stream_tx);
  `uvm_component_utils(stream_sequencer)

  function new(string name = "stream_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass : stream_sequencer

`endif
