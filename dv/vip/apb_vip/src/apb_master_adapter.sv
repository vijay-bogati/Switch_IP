/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_master_adapter.sv
 Module/class Name             : apb_master_adapter
 Author                        : Vijay Bogati
 Description                   : RAL adapter: uvm_reg_bus_op <-> apb_master_tx (byte enables map to pstrb, pslverr maps to UVM_NOT_OK)
***************************************************************/
`ifndef APB_MASTER_ADAPTER_SV
`define APB_MASTER_ADAPTER_SV

class apb_master_adapter extends uvm_reg_adapter;
  `uvm_object_utils(apb_master_adapter)

  function new(string name = "apb_master_adapter");
    super.new(name);
    supports_byte_enable = 1;  // pstrb
    provides_responses   = 0;  // driver updates the request item in place
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    apb_master_tx tx = apb_master_tx::type_id::create("reg2bus_tx");
    tx.paddr       = rw.addr[APB_ADDR_WIDTH-1:0];
    tx.idle_cycles = 0;
    if (rw.kind == UVM_WRITE) begin
      tx.pwrite = APB_WRITE;
      tx.pwdata = rw.data[APB_DATA_WIDTH-1:0];
      tx.pstrb  = rw.byte_en[APB_STRB_WIDTH-1:0];
    end else begin
      tx.pwrite = APB_READ;
      tx.pwdata = '0;
      tx.pstrb  = '0;
    end
    `uvm_info(get_type_name(), {"reg2bus: ", tx.convert2string()}, UVM_HIGH)
    return tx;
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    apb_master_tx tx;
    if (!$cast(tx, bus_item)) begin
      `uvm_fatal(get_type_name(), "bus_item is not an apb_master_tx")
      return;
    end
    rw.kind    = (tx.pwrite == APB_WRITE) ? UVM_WRITE : UVM_READ;
    rw.addr    = tx.paddr;
    rw.data    = (tx.pwrite == APB_WRITE) ? tx.pwdata : tx.prdata;
    rw.byte_en = (tx.pwrite == APB_WRITE) ? tx.pstrb  : '1;
    rw.n_bits  = APB_DATA_WIDTH;
    rw.status  = (tx.pslverr == APB_SLVERR) ? UVM_NOT_OK : UVM_IS_OK;
  endfunction

endclass : apb_master_adapter

`endif
