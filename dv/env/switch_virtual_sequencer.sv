/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_virtual_sequencer.sv
 Module/class Name             : switch_virtual_sequencer
 Author                        : Vijay Bogati
 Description                   : Virtual sequencer: handles to APB and source sequencers, RAL model, scoreboard, env config and control interface
***************************************************************/
`ifndef SWITCH_VIRTUAL_SEQUENCER_SV
`define SWITCH_VIRTUAL_SEQUENCER_SV

class switch_virtual_sequencer extends uvm_sequencer;
  `uvm_component_utils(switch_virtual_sequencer)

  apb_master_sequencer   apb_sqr;
  stream_sequencer       src_sqr [2];
  switch_reg_block       ral;
  switch_scoreboard      sb;
  switch_env_config      cfg;
  virtual switch_ctrl_if ctrl_vif;

  function new(string name = "switch_virtual_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass : switch_virtual_sequencer

`endif
