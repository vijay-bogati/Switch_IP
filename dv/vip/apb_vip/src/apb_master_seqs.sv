/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_master_seqs.sv
 Module/class Name             : apb_master_base_seq, apb_master_rw_seq
 Author                        : Vijay Bogati
 Description                   : APB sequences: base sequence and a single raw read/write access (used for accesses outside the RAL map)
***************************************************************/
`ifndef APB_MASTER_SEQS_SV
`define APB_MASTER_SEQS_SV

class apb_master_base_seq extends uvm_sequence #(apb_master_tx);
  `uvm_object_utils(apb_master_base_seq)

  function new(string name = "apb_master_base_seq");
    super.new(name);
  endfunction
endclass : apb_master_base_seq

// One raw APB access. Set the knobs, start it, then read prdata/pslverr.
class apb_master_rw_seq extends apb_master_base_seq;
  `uvm_object_utils(apb_master_rw_seq)

  bit [APB_ADDR_WIDTH-1:0] addr;
  apb_dir_e                dir   = APB_READ;
  bit [APB_DATA_WIDTH-1:0] wdata;
  bit [APB_STRB_WIDTH-1:0] strb  = '1;

  bit [APB_DATA_WIDTH-1:0] rdata;
  apb_resp_e               resp;

  function new(string name = "apb_master_rw_seq");
    super.new(name);
  endfunction

  task body();
    req = apb_master_tx::type_id::create("req");
    start_item(req);
    if (!req.randomize() with {
          paddr       == local::addr;
          pwrite      == local::dir;
          pwdata      == local::wdata;
          (local::dir == APB_WRITE) -> (pstrb == local::strb);
          idle_cycles == 0;
        })
      `uvm_fatal(get_type_name(), "randomize failed")
    finish_item(req);
    rdata = req.prdata;
    resp  = req.pslverr;
  endtask
endclass : apb_master_rw_seq

`endif
