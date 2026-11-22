/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_master_monitor.sv
 Module/class Name             : apb_master_monitor
 Author                        : Vijay Bogati
 Description                   : APB passive monitor: publishes every completed transfer (psel & penable & pready) on its analysis port
***************************************************************/
`ifndef APB_MASTER_MONITOR_SV
`define APB_MASTER_MONITOR_SV

class apb_master_monitor extends uvm_monitor;
  `uvm_component_utils(apb_master_monitor)

  apb_master_agent_config             cfg;
  virtual apb_if                      vif;
  uvm_analysis_port #(apb_master_tx)  ap;

  function new(string name = "apb_master_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(apb_master_agent_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "apb_master_agent_config not found")
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned waits = 0;
    forever begin
      @(vif.mon_cb);
      if (vif.presetn !== 1'b1) begin
        waits = 0;
        continue;
      end
      if (vif.mon_cb.psel && vif.mon_cb.penable) begin
        if (vif.mon_cb.pready) begin
          apb_master_tx tx = apb_master_tx::type_id::create("tx");
          tx.paddr       = vif.mon_cb.paddr;
          tx.pwrite      = apb_dir_e'(vif.mon_cb.pwrite);
          tx.pwdata      = vif.mon_cb.pwdata;
          tx.pstrb       = vif.mon_cb.pstrb;
          tx.prdata      = vif.mon_cb.prdata;
          tx.pslverr     = apb_resp_e'(vif.mon_cb.pslverr);
          tx.wait_states = waits;
          waits = 0;
          `uvm_info(get_type_name(), {"Observed: ", tx.convert2string()}, UVM_HIGH)
          ap.write(tx);
        end else begin
          waits++;
        end
      end
    end
  endtask

endclass : apb_master_monitor

`endif
