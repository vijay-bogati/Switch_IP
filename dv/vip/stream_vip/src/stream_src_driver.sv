/***************************************************************
 Project name                  : Switch IP
 File Name                     : stream_src_driver.sv
 Module/class Name             : stream_src_driver
 Author                        : Vijay Bogati
 Description                   : Stream source driver: drives header + payload beats with valid gaps, holds data/last until ready, aborts the packet on reset
***************************************************************/
`ifndef STREAM_SRC_DRIVER_SV
`define STREAM_SRC_DRIVER_SV

class stream_src_driver extends uvm_driver #(stream_tx);
  `uvm_component_utils(stream_src_driver)

  stream_agent_config cfg;
  virtual stream_if   vif;
  time                last_hs_time = -1;   // edge of the last completed handshake

  function new(string name = "stream_src_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(stream_agent_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "stream_agent_config not found")
    vif = cfg.vif;
  endfunction

  function void connect_phase(uvm_phase phase);
    vif.src_en = 1'b1;     // take ownership of valid/data/last
  endfunction

  task run_phase(uvm_phase phase);
    idle();
    forever begin
      wait (vif.rst_n === 1'b1);
      seq_item_port.get_next_item(req);
      fork
        drive_pkt(req);
        @(negedge vif.rst_n);
      join_any
      disable fork;
      if (vif.rst_n !== 1'b1) begin
        `uvm_info(get_type_name(), $sformatf("src%0d: reset during packet, aborted", cfg.port_id), UVM_MEDIUM)
        idle();
      end
      seq_item_port.item_done();
    end
  endtask

  function void idle();
    vif.valid_drv <= 1'b0;
    vif.last_drv  <= 1'b0;
    vif.data_drv  <= '0;
  endfunction

  task drive_pkt(stream_tx tx);
    `uvm_info(get_type_name(), $sformatf("src%0d: %s", cfg.port_id, tx.convert2string()), UVM_HIGH)
    // Back-to-back packets: if the previous packet ended at this very edge,
    // drive the next header now (overrides the valid<=0 scheduled below).
    if ($time != last_hs_time) @(vif.src_cb);
    for (int unsigned i = 0; i <= tx.num_beats; i++) begin
      if (tx.gap[i] != 0) begin
        vif.src_cb.valid_drv <= 1'b0;
        vif.src_cb.data_drv  <= $urandom;     // don't care while !valid
        vif.src_cb.last_drv  <= $urandom;
        repeat (tx.gap[i]) @(vif.src_cb);
      end
      vif.src_cb.valid_drv <= 1'b1;
      vif.src_cb.data_drv  <= tx.beat(i);
      vif.src_cb.last_drv  <= (i == tx.num_beats);
      do @(vif.src_cb); while (vif.src_cb.ready !== 1'b1);
      last_hs_time = $time;
    end
    vif.src_cb.valid_drv <= 1'b0;
    vif.src_cb.last_drv  <= 1'b0;
  endtask

endclass : stream_src_driver

`endif
