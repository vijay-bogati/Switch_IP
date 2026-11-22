/***************************************************************
 Project name                  : Switch IP
 File Name                     : stream_monitor.sv
 Module/class Name             : stream_monitor
 Author                        : Vijay Bogati
 Description                   : Stream monitor: publishes every accepted beat (beat_ap) and every complete packet ending in last (pkt_ap); partial packets are dropped on reset
***************************************************************/
`ifndef STREAM_MONITOR_SV
`define STREAM_MONITOR_SV

class stream_monitor extends uvm_monitor;
  `uvm_component_utils(stream_monitor)

  stream_agent_config              cfg;
  virtual stream_if                vif;
  uvm_analysis_port #(stream_beat) beat_ap;
  uvm_analysis_port #(stream_tx)   pkt_ap;

  function new(string name = "stream_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    beat_ap = new("beat_ap", this);
    pkt_ap  = new("pkt_ap",  this);
    if (!uvm_config_db#(stream_agent_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "stream_agent_config not found")
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    stream_tx cur;
    forever begin
      @(vif.mon_cb);
      if (vif.rst_n !== 1'b1) begin
        if (cur != null)
          `uvm_info(get_type_name(), $sformatf("port%0d: partial packet discarded by reset", cfg.port_id), UVM_MEDIUM)
        cur = null;
        continue;
      end
      if (vif.mon_cb.valid && vif.mon_cb.ready) begin
        stream_beat b = stream_beat::type_id::create("b");
        b.data  = vif.mon_cb.data;
        b.last  = vif.mon_cb.last;
        b.first = (cur == null);
        b.stamp = $time;
        beat_ap.write(b);

        if (cur == null) begin
          cur = stream_tx::type_id::create("pkt");
          cur.start_time = $time;
        end
        cur.beats.push_back(b.data);
        if (b.last) begin
          cur.end_time = $time;
          `uvm_info(get_type_name(), $sformatf("port%0d: %s", cfg.port_id, cur.convert2string()), UVM_HIGH)
          pkt_ap.write(cur);
          cur = null;
        end
      end
    end
  endtask

endclass : stream_monitor

`endif
