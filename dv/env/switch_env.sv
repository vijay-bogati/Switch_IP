/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_env.sv
 Module/class Name             : switch_env
 Author                        : Vijay Bogati
 Description                   : Switch IP environment: APB agent + RAL (adapter, explicit predictor), 2 source and 4 sink stream agents, scoreboard, coverage, virtual sequencer
***************************************************************/
`ifndef SWITCH_ENV_SV
`define SWITCH_ENV_SV

class switch_env extends uvm_env;
  `uvm_component_utils(switch_env)

  switch_env_config                    cfg;
  apb_master_agent                     apb_agt;
  stream_agent                         src_agt  [2];
  stream_agent                         dest_agt [4];
  switch_reg_block                     ral;
  apb_master_adapter                   adapter;
  uvm_reg_predictor #(apb_master_tx)   predictor;
  switch_scoreboard                    sb;
  switch_coverage                      cov;
  switch_virtual_sequencer             vsqr;

  function new(string name = "switch_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(switch_env_config)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("NOCFG", "switch_env_config not found")

    uvm_config_db#(apb_master_agent_config)::set(this, "apb_agt", "cfg", cfg.apb_cfg);
    apb_agt = apb_master_agent::type_id::create("apb_agt", this);

    foreach (src_agt[s]) begin
      uvm_config_db#(stream_agent_config)::set(this, $sformatf("src_agt%0d", s), "cfg", cfg.src_cfg[s]);
      src_agt[s] = stream_agent::type_id::create($sformatf("src_agt%0d", s), this);
    end
    foreach (dest_agt[d]) begin
      uvm_config_db#(stream_agent_config)::set(this, $sformatf("dest_agt%0d", d), "cfg", cfg.dest_cfg[d]);
      dest_agt[d] = stream_agent::type_id::create($sformatf("dest_agt%0d", d), this);
    end

    // RAL
    if (ral == null) begin
      ral = switch_reg_block::type_id::create("ral");
      ral.configure(null, "");
      ral.build();
      ral.reset();
    end
    adapter   = apb_master_adapter::type_id::create("adapter");
    predictor = uvm_reg_predictor#(apb_master_tx)::type_id::create("predictor", this);

    if (cfg.has_scoreboard)
      sb = switch_scoreboard::type_id::create("sb", this);
    if (cfg.has_coverage)
      cov = switch_coverage::type_id::create("cov", this);

    vsqr = switch_virtual_sequencer::type_id::create("vsqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    // RAL front door through the APB agent, mirror kept by explicit prediction
    ral.default_map.set_sequencer(apb_agt.sqr, adapter);
    ral.default_map.set_auto_predict(0);
    predictor.map     = ral.default_map;
    predictor.adapter = adapter;
    apb_agt.ap.connect(predictor.bus_in);

    if (cfg.has_scoreboard) begin
      apb_agt.ap.connect(sb.apb_fifo.analysis_export);
      foreach (src_agt[s])  src_agt[s].mon.beat_ap.connect(sb.src_fifo[s].analysis_export);
      foreach (dest_agt[d]) dest_agt[d].mon.pkt_ap.connect(sb.dest_fifo[d].analysis_export);
      sb.cov = cov;
    end

    vsqr.apb_sqr  = apb_agt.sqr;
    foreach (src_agt[s]) vsqr.src_sqr[s] = src_agt[s].sqr;
    vsqr.ral      = ral;
    vsqr.sb       = sb;
    vsqr.cfg      = cfg;
    vsqr.ctrl_vif = cfg.ctrl_vif;
  endfunction

endclass : switch_env

`endif
