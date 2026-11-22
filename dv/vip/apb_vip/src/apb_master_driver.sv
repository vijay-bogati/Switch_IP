/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_master_driver.sv
 Module/class Name             : apb_master_driver
 Author                        : Vijay Bogati
 Description                   : APB4 master driver: setup/access phases, wait-state handling, response returned in the request item, reset aware
***************************************************************/
`ifndef APB_MASTER_DRIVER_SV
`define APB_MASTER_DRIVER_SV

class apb_master_driver extends uvm_driver #(apb_master_tx);
  `uvm_component_utils(apb_master_driver)

  apb_master_agent_config cfg;
  virtual apb_if          vif;
  time                    last_done = -1;   // edge at which the previous transfer completed

  function new(string name = "apb_master_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(apb_master_agent_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "apb_master_agent_config not found")
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    idle_bus();
    forever begin
      wait (vif.presetn === 1'b1);
      seq_item_port.get_next_item(req);
      fork
        drive_transfer(req);
        @(negedge vif.presetn);
      join_any
      disable fork;
      if (vif.presetn !== 1'b1) begin
        `uvm_info(get_type_name(), "Reset during APB transfer, transfer aborted", UVM_MEDIUM)
        req.pslverr = APB_SLVERR;
        idle_bus();
      end
      seq_item_port.item_done();
    end
  endtask

  // asynchronous return to idle (used at start and on reset)
  function void idle_bus();
    vif.psel    <= 1'b0;
    vif.penable <= 1'b0;
    vif.pwrite  <= 1'b0;
    vif.paddr   <= '0;
    vif.pwdata  <= '0;
    vif.pstrb   <= '0;
  endfunction

  task drive_transfer(apb_master_tx tx);
    // Back-to-back: when the previous transfer completed at this very edge
    // and no idle cycles are requested, go straight to SETUP (psel stays high).
    if (tx.idle_cycles != 0 || $time != last_done) begin
      repeat (tx.idle_cycles) @(vif.drv_cb);
      @(vif.drv_cb);
    end
    // SETUP
    vif.drv_cb.psel    <= 1'b1;
    vif.drv_cb.penable <= 1'b0;
    vif.drv_cb.paddr   <= tx.paddr;
    vif.drv_cb.pwrite  <= tx.pwrite;
    vif.drv_cb.pwdata  <= (tx.pwrite == APB_WRITE) ? tx.pwdata : '0;
    vif.drv_cb.pstrb   <= (tx.pwrite == APB_WRITE) ? tx.pstrb  : '0;
    // ACCESS
    @(vif.drv_cb);
    vif.drv_cb.penable <= 1'b1;
    tx.wait_states = 0;
    @(vif.drv_cb);
    while (vif.drv_cb.pready !== 1'b1) begin
      tx.wait_states++;
      if (tx.wait_states > APB_MAX_WAIT_STATES)
        `uvm_error(get_type_name(), $sformatf("pready not seen after %0d wait states", tx.wait_states))
      @(vif.drv_cb);
    end
    tx.prdata  = vif.drv_cb.prdata;
    tx.pslverr = apb_resp_e'(vif.drv_cb.pslverr);
    last_done  = $time;
    vif.drv_cb.psel    <= 1'b0;   // overridden by a back-to-back SETUP in this timestep
    vif.drv_cb.penable <= 1'b0;
    `uvm_info(get_type_name(), {"Driven: ", tx.convert2string()}, UVM_HIGH)
  endtask

endclass : apb_master_driver

`endif
