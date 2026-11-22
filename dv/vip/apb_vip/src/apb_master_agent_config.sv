/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_master_agent_config.sv
 Module/class Name             : apb_master_agent_config
 Author                        : Vijay Bogati
 Description                   : APB master agent configuration (active/passive, coverage enable, virtual interface)
***************************************************************/
`ifndef APB_MASTER_AGENT_CONFIG_SV
`define APB_MASTER_AGENT_CONFIG_SV

class apb_master_agent_config extends uvm_object;
  `uvm_object_utils(apb_master_agent_config)

  uvm_active_passive_enum is_active    = UVM_ACTIVE;
  bit                     has_coverage = 1;
  virtual apb_if          vif;

  function new(string name = "apb_master_agent_config");
    super.new(name);
  endfunction

endclass : apb_master_agent_config

`endif
