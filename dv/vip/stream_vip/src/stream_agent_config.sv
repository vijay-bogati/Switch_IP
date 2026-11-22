/***************************************************************
 Project name                  : Switch IP
 File Name                     : stream_agent_config.sv
 Module/class Name             : stream_agent_config
 Author                        : Vijay Bogati
 Description                   : Stream agent configuration: source or sink role, active/passive, sink ready percentage (can be changed at run time)
***************************************************************/
`ifndef STREAM_AGENT_CONFIG_SV
`define STREAM_AGENT_CONFIG_SV

typedef enum bit { STREAM_SOURCE = 1'b0, STREAM_SINK = 1'b1 } stream_role_e;

class stream_agent_config extends uvm_object;
  `uvm_object_utils(stream_agent_config)

  uvm_active_passive_enum is_active = UVM_ACTIVE;
  stream_role_e           role      = STREAM_SOURCE;
  int unsigned            port_id   = 0;      // for messages only

  // sink only: probability (0..100) that ready is high in a cycle
  int unsigned            ready_pct = 100;

  virtual stream_if       vif;

  function new(string name = "stream_agent_config");
    super.new(name);
  endfunction

endclass : stream_agent_config

`endif
