/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_master_tx.sv
 Module/class Name             : apb_master_tx
 Author                        : Vijay Bogati
 Description                   : APB transfer sequence item (request fields plus prdata/pslverr response captured by the driver/monitor)
***************************************************************/
`ifndef APB_MASTER_TX_SV
`define APB_MASTER_TX_SV

class apb_master_tx extends uvm_sequence_item;

  rand bit [APB_ADDR_WIDTH-1:0] paddr;
  rand apb_dir_e                pwrite;
  rand bit [APB_DATA_WIDTH-1:0] pwdata;
  rand bit [APB_STRB_WIDTH-1:0] pstrb;
  rand int unsigned             idle_cycles;   // idle cycles before the setup phase

  // response
  bit [APB_DATA_WIDTH-1:0]      prdata;
  apb_resp_e                    pslverr;
  int unsigned                  wait_states;

  `uvm_object_utils_begin(apb_master_tx)
    `uvm_field_int (paddr,                 UVM_ALL_ON | UVM_HEX)
    `uvm_field_enum(apb_dir_e, pwrite,     UVM_ALL_ON)
    `uvm_field_int (pwdata,                UVM_ALL_ON | UVM_HEX)
    `uvm_field_int (pstrb,                 UVM_ALL_ON | UVM_BIN)
    `uvm_field_int (prdata,                UVM_ALL_ON | UVM_HEX)
    `uvm_field_enum(apb_resp_e, pslverr,   UVM_ALL_ON)
    `uvm_field_int (wait_states,           UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int (idle_cycles,           UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
  `uvm_object_utils_end

  // word aligned accesses
  constraint c_align  { paddr[1:0] == 2'b00; }
  // APB4: pstrb is zero for reads
  constraint c_rd_strb { (pwrite == APB_READ) -> (pstrb == '0); }
  constraint c_wr_strb { soft (pwrite == APB_WRITE) -> (pstrb == '1); }
  constraint c_idle   { soft idle_cycles inside {[0:2]}; }

  function new(string name = "apb_master_tx");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("%s addr=0x%03h %s strb=%b rdata=0x%08h %s",
                     pwrite.name(), paddr,
                     (pwrite == APB_WRITE) ? $sformatf("wdata=0x%08h", pwdata) : "",
                     pstrb, prdata, pslverr.name());
  endfunction

endclass : apb_master_tx

`endif
