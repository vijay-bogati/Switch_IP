/***************************************************************
 Project name                  : Switch IP
 File Name                     : stream_sink_driver.sv
 Module/class Name             : stream_sink_driver
 Author                        : Vijay Bogati
 Description                   : Stream sink driver: free-running ready generator, ready high with probability cfg.ready_pct each cycle
***************************************************************/
`ifndef STREAM_SINK_DRIVER_SV
`define STREAM_SINK_DRIVER_SV

class stream_sink_driver extends uvm_driver #(stream_tx);   // ready generator only: seq_item_port unused
  `uvm_component_utils(stream_sink_driver)

  stream_agent_config cfg;
  virtual stream_if   vif;

  function new(string name = "stream_sink_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(stream_agent_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "stream_agent_config not found")
    vif = cfg.vif;
  endfunction

  function void connect_phase(uvm_phase phase);
    vif.sink_en = 1'b1;    // take ownership of ready
  endfunction

  task run_phase(uvm_phase phase);
    vif.ready_drv <= 1'b0;
    forever begin
      @(vif.sink_cb);
      vif.sink_cb.ready_drv <= ($urandom_range(99) < cfg.ready_pct);
    end
  endtask

endclass : stream_sink_driver

`endif
