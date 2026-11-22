/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_assertions.sv
 Module/class Name             : apb_assertions
 Author                        : Vijay Bogati
 Description                   : APB4 protocol checker (master and slave side rules), instantiated next to apb_if
***************************************************************/
`ifndef APB_ASSERTIONS_SV
`define APB_ASSERTIONS_SV

module apb_assertions
  import apb_global_pkg::*;
(
  input logic                      pclk,
  input logic                      presetn,
  input logic [APB_ADDR_WIDTH-1:0] paddr,
  input logic                      psel,
  input logic                      penable,
  input logic                      pwrite,
  input logic [APB_DATA_WIDTH-1:0] pwdata,
  input logic [APB_STRB_WIDTH-1:0] pstrb,
  input logic [APB_DATA_WIDTH-1:0] prdata,
  input logic                      pready,
  input logic                      pslverr
);

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  default clocking cb @(posedge pclk); endclocking
  default disable iff (!presetn);

  //------------------------- master side -------------------------
  // psel must never be X out of reset
  property p_psel_known;  !$isunknown(psel); endproperty
  APB_M_PSEL_KNOWN:   assert property (p_psel_known)
    else `uvm_error("APB_SVA", $sformatf("APB: psel is X/Z"))

  // penable only together with psel
  property p_penable_with_psel; penable |-> psel; endproperty
  APB_M_PENABLE_PSEL: assert property (p_penable_with_psel)
    else `uvm_error("APB_SVA", $sformatf("APB: penable high without psel"))

  // setup phase is followed by access phase
  property p_setup_to_access; (psel && !penable) |=> (psel && penable); endproperty
  APB_M_SETUP_ACCESS: assert property (p_setup_to_access)
    else `uvm_error("APB_SVA", $sformatf("APB: setup phase not followed by access phase"))

  // control/data stable from setup until completion
  property p_ctrl_stable;
    (psel && !(penable && pready)) |=>
      $stable(paddr) && $stable(pwrite) && $stable(pstrb) && (!pwrite || $stable(pwdata));
  endproperty
  APB_M_CTRL_STABLE:  assert property (p_ctrl_stable)
    else `uvm_error("APB_SVA", $sformatf("APB: address/control/write data changed during transfer"))

  // pstrb must be 0 for reads (APB4)
  property p_read_strb; (psel && !pwrite) |-> (pstrb == '0); endproperty
  APB_M_READ_STRB:    assert property (p_read_strb)
    else `uvm_error("APB_SVA", $sformatf("APB: pstrb not zero during read"))

  // control signals known while selected
  property p_ctrl_known; psel |-> !$isunknown({paddr, pwrite, penable, pstrb}); endproperty
  APB_M_CTRL_KNOWN:   assert property (p_ctrl_known)
    else `uvm_error("APB_SVA", $sformatf("APB: control X/Z while psel"))

  //------------------------- slave side --------------------------
  property p_pready_known; (psel && penable) |-> !$isunknown(pready); endproperty
  APB_S_PREADY_KNOWN: assert property (p_pready_known)
    else `uvm_error("APB_SVA", $sformatf("APB: pready X/Z in access phase"))

  property p_resp_known; (psel && penable && pready) |-> !$isunknown(pslverr); endproperty
  APB_S_PSLVERR_KNOWN: assert property (p_resp_known)
    else `uvm_error("APB_SVA", $sformatf("APB: pslverr X/Z at completion"))

  property p_rdata_known; (psel && penable && pready && !pwrite) |-> !$isunknown(prdata); endproperty
  APB_S_PRDATA_KNOWN: assert property (p_rdata_known)
    else `uvm_error("APB_SVA", $sformatf("APB: prdata X/Z on read completion"))

  // transfer completes within the allowed number of wait states
  property p_no_hang; (psel && penable && !pready) |-> ##[1:APB_MAX_WAIT_STATES] pready; endproperty
  APB_S_NO_HANG:      assert property (p_no_hang)
    else `uvm_error("APB_SVA", $sformatf("APB: pready not returned within %0d cycles", APB_MAX_WAIT_STATES))

  //------------------------- coverage ----------------------------
  APB_C_WRITE:  cover property (psel && penable && pready &&  pwrite);
  APB_C_READ:   cover property (psel && penable && pready && !pwrite);
  APB_C_SLVERR: cover property (psel && penable && pready &&  pslverr);
  APB_C_B2B:    cover property ((psel && penable && pready) ##1 (psel && !penable));

endmodule : apb_assertions

`endif
