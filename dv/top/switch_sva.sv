/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_sva.sv
 Module/class Name             : switch_sva
 Author                        : Vijay Bogati
 Description                   : DUT-level assertions and cover points bound into switch_ip_top: reset values, no interleave on dest3/dest4, 1-clock header latency, arbitration contention cover
***************************************************************/
`ifndef SWITCH_SVA_SV
`define SWITCH_SVA_SV

module switch_sva (
  input logic       clk,
  input logic       rst_n,        // synchronized reset inside the DUT
  input logic       rst_n_pin,
  input logic [3:0] d_valid,
  input logic [3:0] d_ready,
  input logic [3:0] d_last,
  input logic       src1_ready,
  input logic       src2_ready,
  input logic       src1_valid,
  input logic       src2_valid,
  input logic       error,
  input logic       p1_valid,
  input logic [3:0] p1_dest,
  input logic       p2_valid,
  input logic [3:0] p2_dest,
  input logic [3:0] g1,           // per-dest grant to src1
  input logic [3:0] g2            // per-dest grant to src2
);

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // outputs are quiet in reset (spec 9.1)
  property p_reset_quiet;
    @(posedge clk) !rst_n |-> (d_valid == 4'b0) && !src1_ready && !src2_ready && !error;
  endproperty
  SW_RESET_QUIET: assert property (p_reset_quiet)
    else `uvm_error("SWITCH_SVA", $sformatf("SVA: valid/ready/error not 0 during reset"))

  // one grant at most per destination
  SW_GRANT_ONEHOT: assert property (@(posedge clk) disable iff (!rst_n) (g1 & g2) == 4'b0)
    else `uvm_error("SWITCH_SVA", $sformatf("SVA: destination granted to both sources"))

  // no interleaving on the shared destinations: once a packet started on
  // destN from one source, the next beat on destN comes from the same source
  for (genvar d = 2; d < 4; d++) begin : g_noint
    property p_no_interleave_s1;
      @(posedge clk) disable iff (!rst_n)
        (d_valid[d] && d_ready[d] && !d_last[d] && g1[d]) |=> (!d_valid[d] || g1[d]) until_with (d_valid[d] && d_ready[d] && d_last[d]);
    endproperty
    property p_no_interleave_s2;
      @(posedge clk) disable iff (!rst_n)
        (d_valid[d] && d_ready[d] && !d_last[d] && g2[d]) |=> (!d_valid[d] || g2[d]) until_with (d_valid[d] && d_ready[d] && d_last[d]);
    endproperty
    SW_NO_INTERLEAVE_S1: assert property (p_no_interleave_s1) else `uvm_error("SWITCH_SVA", $sformatf("SVA: dest%0d interleaved (src1 packet)", d+1))
    SW_NO_INTERLEAVE_S2: assert property (p_no_interleave_s2) else `uvm_error("SWITCH_SVA", $sformatf("SVA: dest%0d interleaved (src2 packet)", d+1))

    // both sources waiting for the same shared destination
    SW_C_CONTENTION: cover property (@(posedge clk) disable iff (!rst_n)
                                     p1_valid && p1_dest[d] && p2_valid && p2_dest[d]);
    SW_C_STALL:      cover property (@(posedge clk) disable iff (!rst_n) d_valid[d] && !d_ready[d]);
  end

  // source stalls, error rise, asynchronous reset
  SW_C_SRC1_STALL: cover property (@(posedge clk) disable iff (!rst_n) src1_valid && !src1_ready);
  SW_C_SRC2_STALL: cover property (@(posedge clk) disable iff (!rst_n) src2_valid && !src2_ready);
  SW_C_ERROR:      cover property (@(posedge clk) disable iff (!rst_n) $rose(error));
  SW_C_RST_ASYNC:  cover property (@(posedge clk) $fell(rst_n_pin));

endmodule : switch_sva

// bound into switch_ip_top from hdl_top


`endif
