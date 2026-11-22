/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_env_config.sv
 Module/class Name             : switch_env_config
 Author                        : Vijay Bogati
 Description                   : Environment configuration: agent configs (APB, 2 sources, 4 sinks), scoreboard/coverage enables, control interface
***************************************************************/
`ifndef SWITCH_ENV_CONFIG_SV
`define SWITCH_ENV_CONFIG_SV

class switch_env_config extends uvm_object;
  `uvm_object_utils(switch_env_config)

  apb_master_agent_config apb_cfg;
  stream_agent_config     src_cfg  [2];
  stream_agent_config     dest_cfg [4];

  bit has_scoreboard = 1;
  bit has_coverage   = 1;

  // allow expected packets to remain at end of test (e.g. reset tests)
  bit allow_leftover = 0;

  virtual switch_ctrl_if ctrl_vif;

  function new(string name = "switch_env_config");
    super.new(name);
  endfunction

  // set ready percentage on all destination sinks
  function void set_ready_pct(int unsigned pct);
    foreach (dest_cfg[d]) dest_cfg[d].ready_pct = pct;
  endfunction

endclass : switch_env_config

`endif
