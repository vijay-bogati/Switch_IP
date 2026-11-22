/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_master_coverage.sv
 Module/class Name             : apb_master_coverage
 Author                        : Vijay Bogati
 Description                   : APB functional coverage: direction, strobes, response, wait states and address windows
***************************************************************/
`ifndef APB_MASTER_COVERAGE_SV
`define APB_MASTER_COVERAGE_SV

class apb_master_coverage extends uvm_subscriber #(apb_master_tx);
  `uvm_component_utils(apb_master_coverage)

  apb_master_tx tx;

  covergroup cg_apb;
    option.per_instance = 1;
    cp_dir   : coverpoint tx.pwrite;
    cp_resp  : coverpoint tx.pslverr;
    cp_strb  : coverpoint tx.pstrb iff (tx.pwrite == APB_WRITE) {
      bins all_bytes = {4'hF};
      bins none      = {4'h0};
      bins single[]  = {4'h1, 4'h2, 4'h4, 4'h8};
      bins partial   = default;
    }
    cp_waits : coverpoint tx.wait_states {
      bins zero = {0};
      // the Switch IP slave has zero wait states (pready tied to 1, spec 2)
      ignore_bins some = {[1:$]};
    }
    cp_addr  : coverpoint tx.paddr {
      bins low_window  = {[12'h000:12'h04C]};
      bins high_window = {[12'h050:12'hFFC]};
    }
    x_dir_resp : cross cp_dir, cp_resp;
  endgroup

  function new(string name = "apb_master_coverage", uvm_component parent = null);
    super.new(name, parent);
    cg_apb = new();
  endfunction

  function void write(apb_master_tx t);
    tx = t;
    cg_apb.sample();
  endfunction

endclass : apb_master_coverage

`endif
