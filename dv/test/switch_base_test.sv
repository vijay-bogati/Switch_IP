/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_base_test.sv
 Module/class Name             : switch_base_test
 Author                        : Vijay Bogati
 Description                   : Base test: builds env config from the interfaces in hdl_top, applies reset, runs the virtual sequence (selected by factory override in derived tests), prints PASS/FAIL
***************************************************************/
`ifndef SWITCH_BASE_TEST_SV
`define SWITCH_BASE_TEST_SV

class switch_base_test extends uvm_test;
  `uvm_component_utils(switch_base_test)

  switch_env        env;
  switch_env_config cfg;
  time              test_timeout = 50ms;

  function new(string name = "switch_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = switch_env_config::type_id::create("cfg");

    if (!uvm_config_db#(virtual switch_ctrl_if)::get(this, "", "ctrl_vif", cfg.ctrl_vif))
      `uvm_fatal("NOVIF", "ctrl_vif not found")

    cfg.apb_cfg = apb_master_agent_config::type_id::create("apb_cfg");
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", cfg.apb_cfg.vif))
      `uvm_fatal("NOVIF", "apb_vif not found")

    foreach (cfg.src_cfg[s]) begin
      cfg.src_cfg[s] = stream_agent_config::type_id::create($sformatf("src_cfg%0d", s));
      cfg.src_cfg[s].role    = STREAM_SOURCE;
      cfg.src_cfg[s].port_id = s + 1;
      if (!uvm_config_db#(virtual stream_if)::get(this, "", $sformatf("src_vif%0d", s), cfg.src_cfg[s].vif))
        `uvm_fatal("NOVIF", $sformatf("src_vif%0d not found", s))
    end
    foreach (cfg.dest_cfg[d]) begin
      cfg.dest_cfg[d] = stream_agent_config::type_id::create($sformatf("dest_cfg%0d", d));
      cfg.dest_cfg[d].role      = STREAM_SINK;
      cfg.dest_cfg[d].port_id   = d + 1;
      cfg.dest_cfg[d].ready_pct = 100;
      if (!uvm_config_db#(virtual stream_if)::get(this, "", $sformatf("dest_vif%0d", d), cfg.dest_cfg[d].vif))
        `uvm_fatal("NOVIF", $sformatf("dest_vif%0d not found", d))
    end

    configure_test();

    uvm_config_db#(switch_env_config)::set(this, "*", "env_cfg", cfg);
    env = switch_env::type_id::create("env", this);
  endfunction

  // hook for derived tests (knobs, overrides)
  virtual function void configure_test();
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    if (uvm_report_enabled(UVM_HIGH)) uvm_top.print_topology();
  endfunction

  task run_phase(uvm_phase phase);
    switch_base_vseq vseq;
    phase.raise_objection(this);
    cfg.ctrl_vif.apply_reset();
    // watchdog in this package's time units (uvm_top.set_timeout uses UVM's)
    fork
      begin
        #(test_timeout);
        `uvm_fatal("TIMEOUT", $sformatf("test did not finish within %0t", test_timeout))
      end
    join_none
    vseq = switch_base_vseq::type_id::create("vseq");
    `uvm_info(get_type_name(), $sformatf("Running %s", vseq.get_type_name()), UVM_LOW)
    vseq.start(env.vsqr);
    cfg.ctrl_vif.wait_cycles(20);
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server rs = uvm_report_server::get_server();
    int n_err = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
    $display("\n==========================================================");
    $display(" TEST %s : %s  (UVM_ERROR+FATAL = %0d)", get_type_name(),
             (n_err == 0) ? "PASSED" : "FAILED", n_err);
    $display("==========================================================\n");
  endfunction

endclass : switch_base_test

`endif
