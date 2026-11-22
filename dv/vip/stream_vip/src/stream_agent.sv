/***************************************************************
 Project name                  : Switch IP
 File Name                     : stream_agent.sv
 Module/class Name             : stream_agent
 Author                        : Vijay Bogati
 Description                   : Stream agent: source role builds sequencer + source driver, sink role builds the ready driver; monitor always present
***************************************************************/
`ifndef STREAM_AGENT_SV
`define STREAM_AGENT_SV

class stream_agent extends uvm_agent;
  `uvm_component_utils(stream_agent)

  stream_agent_config cfg;
  stream_sequencer    sqr;
  stream_src_driver   src_drv;
  stream_sink_driver  sink_drv;
  stream_monitor      mon;

  function new(string name = "stream_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(stream_agent_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "stream_agent_config not found")
    uvm_config_db#(stream_agent_config)::set(this, "*", "cfg", cfg);

    mon = stream_monitor::type_id::create("mon", this);
    if (cfg.is_active == UVM_ACTIVE) begin
      if (cfg.role == STREAM_SOURCE) begin
        sqr     = stream_sequencer::type_id::create("sqr", this);
        src_drv = stream_src_driver::type_id::create("src_drv", this);
      end else begin
        sink_drv = stream_sink_driver::type_id::create("sink_drv", this);
      end
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (cfg.is_active == UVM_ACTIVE && cfg.role == STREAM_SOURCE)
      src_drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : stream_agent

`endif
