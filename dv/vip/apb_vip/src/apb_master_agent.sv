/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_master_agent.sv
 Module/class Name             : apb_master_agent
 Author                        : Vijay Bogati
 Description                   : APB master agent: sequencer, driver (active only), monitor and coverage subscriber
***************************************************************/
`ifndef APB_MASTER_AGENT_SV
`define APB_MASTER_AGENT_SV

class apb_master_agent extends uvm_agent;
  `uvm_component_utils(apb_master_agent)

  apb_master_agent_config cfg;
  apb_master_sequencer    sqr;
  apb_master_driver       drv;
  apb_master_monitor      mon;
  apb_master_coverage     cov;

  uvm_analysis_port #(apb_master_tx) ap;

  function new(string name = "apb_master_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(apb_master_agent_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "apb_master_agent_config not found")
    uvm_config_db#(apb_master_agent_config)::set(this, "*", "cfg", cfg);

    mon = apb_master_monitor::type_id::create("mon", this);
    if (cfg.is_active == UVM_ACTIVE) begin
      sqr = apb_master_sequencer::type_id::create("sqr", this);
      drv = apb_master_driver::type_id::create("drv", this);
    end
    if (cfg.has_coverage)
      cov = apb_master_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    ap = mon.ap;
    if (cfg.is_active == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
    if (cfg.has_coverage)
      mon.ap.connect(cov.analysis_export);
  endfunction

endclass : apb_master_agent

`endif
