/***************************************************************
 Project name                  : Switch IP
 File Name                     : stream_if.sv
 Module/class Name             : stream_if
 Author                        : Vijay Bogati
 Description                   : valid/ready packet stream interface (data, last) with source/sink/monitor clocking blocks and handshake assertions
***************************************************************/
`ifndef STREAM_IF_SV
`define STREAM_IF_SV

interface stream_if (input logic clk, input logic rst_n);
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Bus nets: driven either by the DUT or by the testbench, never both.
  // The testbench drives through *_drv and only for the role it owns.
  wire         valid;
  wire         ready;
  wire  [31:0] data;
  wire         last;

  logic        valid_drv = 1'b0;
  logic [31:0] data_drv  = '0;
  logic        last_drv  = 1'b0;
  logic        ready_drv = 1'b0;
  bit          src_en    = 1'b0;   // TB is the source (drives valid/data/last)
  bit          sink_en   = 1'b0;   // TB is the sink   (drives ready)

  assign valid = src_en  ? valid_drv : 1'bz;
  assign data  = src_en  ? data_drv  : 'z;
  assign last  = src_en  ? last_drv  : 1'bz;
  assign ready = sink_en ? ready_drv : 1'bz;

  // Source side (TB drives valid/data/last)
  clocking src_cb @(posedge clk);
    default input #1step output #1;
    output valid_drv, data_drv, last_drv;
    input  ready;
  endclocking

  // Sink side (TB drives ready)
  clocking sink_cb @(posedge clk);
    default input #1step output #1;
    output ready_drv;
    input  valid, data, last;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input valid, ready, data, last;
  endclocking

  modport SOURCE  (clocking src_cb,  input clk, rst_n);
  modport SINK    (clocking sink_cb, input clk, rst_n);
  modport MONITOR (clocking mon_cb,  input clk, rst_n);

  //-------------------------------------------------------------
  // Handshake rules (spec section 2): once valid is high, data and
  // last are held stable until ready is seen high.
  //-------------------------------------------------------------
  bit checks_enable = 1;

  property p_valid_hold;
    @(posedge clk) disable iff (!rst_n || !checks_enable)
      (valid && !ready) |=> valid;
  endproperty
  STREAM_VALID_HOLD: assert property (p_valid_hold)
    else `uvm_error("STREAM_SVA", $sformatf("%m: valid dropped before ready"))

  property p_payload_stable;
    @(posedge clk) disable iff (!rst_n || !checks_enable)
      (valid && !ready) |=> ($stable(data) && $stable(last));
  endproperty
  STREAM_DATA_STABLE: assert property (p_payload_stable)
    else `uvm_error("STREAM_SVA", $sformatf("%m: data/last changed while valid && !ready"))

  property p_valid_known;
    @(posedge clk) disable iff (!rst_n || !checks_enable)
      !$isunknown(valid) && !$isunknown(ready);
  endproperty
  STREAM_VR_KNOWN: assert property (p_valid_known)
    else `uvm_error("STREAM_SVA", $sformatf("%m: valid/ready X/Z"))

  property p_data_known;
    @(posedge clk) disable iff (!rst_n || !checks_enable)
      valid |-> !$isunknown({data, last});
  endproperty
  STREAM_DATA_KNOWN: assert property (p_data_known)
    else `uvm_error("STREAM_SVA", $sformatf("%m: data/last X/Z while valid"))

  STREAM_C_STALL: cover property (@(posedge clk) disable iff (!rst_n) valid && !ready);
  STREAM_C_B2B:   cover property (@(posedge clk) disable iff (!rst_n) (valid && ready) ##1 (valid && ready));

endinterface : stream_if

`endif
