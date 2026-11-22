/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_master_sequencer.sv
 Module/class Name             : apb_master_sequencer
 Author                        : Vijay Bogati
 Description                   : APB master sequencer (also the sequencer used by the RAL default map)
***************************************************************/
`ifndef APB_MASTER_SEQUENCER_SV
`define APB_MASTER_SEQUENCER_SV

class apb_master_sequencer extends uvm_sequencer #(apb_master_tx);
  `uvm_component_utils(apb_master_sequencer)

  function new(string name = "apb_master_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass : apb_master_sequencer

`endif
