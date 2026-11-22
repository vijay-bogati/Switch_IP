/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_reg_block.sv
 Module/class Name             : switch_reg_block (+ register classes)
 Author                        : Vijay Bogati
 Description                   : UVM RAL model of the Switch IP CSR map (spec section 6). Status, capture and counter registers are volatile
***************************************************************/
`ifndef SWITCH_REG_BLOCK_SV
`define SWITCH_REG_BLOCK_SV

//------------------------------------------------------------------
// 0x000 CTRL
//------------------------------------------------------------------
class switch_ctrl_reg extends uvm_reg;
  `uvm_object_utils(switch_ctrl_reg)
  rand uvm_reg_field switch_en;

  function new(string name = "switch_ctrl_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    switch_en = uvm_reg_field::type_id::create("switch_en");
    //                  parent size lsb access volatile reset has_reset rand indiv
    switch_en.configure(this, 1,   0,  "RW",  0,       1'b0, 1,        1,   0);
  endfunction
endclass

//------------------------------------------------------------------
// 0x004 ROUTE_CFG: [3:0] src1 -> dest4..dest1, [7:4] src2 -> dest4..dest1
// src1->dest2 (bit 1) and src2->dest1 (bit 4) are tied to 0 (RO)
//------------------------------------------------------------------
class switch_route_cfg_reg extends uvm_reg;
  `uvm_object_utils(switch_route_cfg_reg)
  rand uvm_reg_field s1_d1, s1_d2, s1_d3, s1_d4;
  rand uvm_reg_field s2_d1, s2_d2, s2_d3, s2_d4;

  function new(string name = "switch_route_cfg_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    s1_d1 = uvm_reg_field::type_id::create("s1_d1");
    s1_d2 = uvm_reg_field::type_id::create("s1_d2");
    s1_d3 = uvm_reg_field::type_id::create("s1_d3");
    s1_d4 = uvm_reg_field::type_id::create("s1_d4");
    s2_d1 = uvm_reg_field::type_id::create("s2_d1");
    s2_d2 = uvm_reg_field::type_id::create("s2_d2");
    s2_d3 = uvm_reg_field::type_id::create("s2_d3");
    s2_d4 = uvm_reg_field::type_id::create("s2_d4");
    s1_d1.configure(this, 1, 0, "RW", 0, 1'b1, 1, 1, 0);
    s1_d2.configure(this, 1, 1, "RO", 0, 1'b0, 1, 0, 0);
    s1_d3.configure(this, 1, 2, "RW", 0, 1'b1, 1, 1, 0);
    s1_d4.configure(this, 1, 3, "RW", 0, 1'b1, 1, 1, 0);
    s2_d1.configure(this, 1, 4, "RO", 0, 1'b0, 1, 0, 0);
    s2_d2.configure(this, 1, 5, "RW", 0, 1'b1, 1, 1, 0);
    s2_d3.configure(this, 1, 6, "RW", 0, 1'b1, 1, 1, 0);
    s2_d4.configure(this, 1, 7, "RW", 0, 1'b1, 1, 1, 0);
  endfunction
endclass

//------------------------------------------------------------------
// 0x008 MAX_PAYLOAD
//------------------------------------------------------------------
class switch_max_payload_reg extends uvm_reg;
  `uvm_object_utils(switch_max_payload_reg)
  rand uvm_reg_field max_payload;

  function new(string name = "switch_max_payload_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    max_payload = uvm_reg_field::type_id::create("max_payload");
    max_payload.configure(this, 8, 0, "RW", 0, 8'hFF, 1, 1, 0);
  endfunction
endclass

//------------------------------------------------------------------
// 0x010..0x02C DESTn_BASE / DESTn_LIMIT (12-bit address)
//------------------------------------------------------------------
class switch_addr_reg extends uvm_reg;
  `uvm_object_utils(switch_addr_reg)
  rand uvm_reg_field addr;
  bit [11:0] reset_val;

  function new(string name = "switch_addr_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    addr = uvm_reg_field::type_id::create("addr");
    addr.configure(this, 12, 0, "RW", 0, reset_val, 1, 1, 0);
  endfunction
endclass

//------------------------------------------------------------------
// 0x030 ERR_STATUS (W1C) / 0x034 ERR_MASK (RW)
// src1 [4:0], src2 [12:8]: ILLEGAL, DISABLED, UNMAPPED, SRCID, LEN; [16] CFG_OVERLAP
//------------------------------------------------------------------
class switch_err_reg extends uvm_reg;
  `uvm_object_utils(switch_err_reg)
  rand uvm_reg_field s1_illegal, s1_disabled, s1_unmapped, s1_srcid, s1_len;
  rand uvm_reg_field s2_illegal, s2_disabled, s2_unmapped, s2_srcid, s2_len;
  rand uvm_reg_field cfg_overlap;

  string acc       = "W1C";
  bit    is_vol    = 1;
  bit    reset_one = 0;

  function new(string name = "switch_err_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  local function uvm_reg_field mk(string n, int lsb);
    uvm_reg_field f = uvm_reg_field::type_id::create(n);
    f.configure(this, 1, lsb, acc, is_vol, reset_one, 1, 1, 0);
    return f;
  endfunction

  virtual function void build();
    s1_illegal  = mk("s1_illegal",  0);
    s1_disabled = mk("s1_disabled", 1);
    s1_unmapped = mk("s1_unmapped", 2);
    s1_srcid    = mk("s1_srcid",    3);
    s1_len      = mk("s1_len",      4);
    s2_illegal  = mk("s2_illegal",  8);
    s2_disabled = mk("s2_disabled", 9);
    s2_unmapped = mk("s2_unmapped", 10);
    s2_srcid    = mk("s2_srcid",    11);
    s2_len      = mk("s2_len",      12);
    cfg_overlap = mk("cfg_overlap", 16);
  endfunction
endclass

//------------------------------------------------------------------
// 0x038 / 0x03C ERR_HDR_SRCn, 0x040 / 0x044 PKT_CNT_SRCn (RO, volatile)
//------------------------------------------------------------------
class switch_ro32_reg extends uvm_reg;
  `uvm_object_utils(switch_ro32_reg)
  uvm_reg_field value;

  function new(string name = "switch_ro32_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    value = uvm_reg_field::type_id::create("value");
    value.configure(this, 32, 0, "RO", 1, 32'h0, 1, 0, 0);
  endfunction
endclass

//------------------------------------------------------------------
// 0x048 DROP_CNT: [15:0] src1, [31:16] src2 (saturating)
//------------------------------------------------------------------
class switch_drop_cnt_reg extends uvm_reg;
  `uvm_object_utils(switch_drop_cnt_reg)
  uvm_reg_field src1, src2;

  function new(string name = "switch_drop_cnt_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    src1 = uvm_reg_field::type_id::create("src1");
    src2 = uvm_reg_field::type_id::create("src2");
    src1.configure(this, 16, 0,  "RO", 1, 16'h0, 1, 0, 0);
    src2.configure(this, 16, 16, "RO", 1, 16'h0, 1, 0, 0);
  endfunction
endclass

//------------------------------------------------------------------
// 0x04C ID_VERSION
//------------------------------------------------------------------
class switch_id_version_reg extends uvm_reg;
  `uvm_object_utils(switch_id_version_reg)
  uvm_reg_field version, ip_id;

  function new(string name = "switch_id_version_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    version = uvm_reg_field::type_id::create("version");
    ip_id   = uvm_reg_field::type_id::create("ip_id");
    version.configure(this, 16, 0,  "RO", 0, 16'h0100, 1, 0, 0);
    ip_id.configure  (this, 16, 16, "RO", 0, 16'h5357, 1, 0, 0);
  endfunction
endclass

//------------------------------------------------------------------
// Register block
//------------------------------------------------------------------
class switch_reg_block extends uvm_reg_block;
  `uvm_object_utils(switch_reg_block)

  rand switch_ctrl_reg        ctrl;
  rand switch_route_cfg_reg   route_cfg;
  rand switch_max_payload_reg max_payload;
  rand switch_addr_reg        dest_base  [4];
  rand switch_addr_reg        dest_limit [4];
  rand switch_err_reg         err_status;
  rand switch_err_reg         err_mask;
       switch_ro32_reg        err_hdr    [2];
       switch_ro32_reg        pkt_cnt    [2];
       switch_drop_cnt_reg    drop_cnt;
       switch_id_version_reg  id_version;

  function new(string name = "switch_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    default_map = create_map("default_map", 'h0, 4, UVM_LITTLE_ENDIAN, 1);

    ctrl = switch_ctrl_reg::type_id::create("ctrl");
    ctrl.configure(this); ctrl.build();
    default_map.add_reg(ctrl, 'h000, "RW");

    route_cfg = switch_route_cfg_reg::type_id::create("route_cfg");
    route_cfg.configure(this); route_cfg.build();
    default_map.add_reg(route_cfg, 'h004, "RW");

    max_payload = switch_max_payload_reg::type_id::create("max_payload");
    max_payload.configure(this); max_payload.build();
    default_map.add_reg(max_payload, 'h008, "RW");

    foreach (dest_base[i]) begin
      dest_base[i] = switch_addr_reg::type_id::create($sformatf("dest%0d_base", i+1));
      dest_base[i].reset_val = 12'(i * 'h100);
      dest_base[i].configure(this); dest_base[i].build();
      default_map.add_reg(dest_base[i], 'h010 + 8*i, "RW");

      dest_limit[i] = switch_addr_reg::type_id::create($sformatf("dest%0d_limit", i+1));
      dest_limit[i].reset_val = 12'(i * 'h100 + 'hFF);
      dest_limit[i].configure(this); dest_limit[i].build();
      default_map.add_reg(dest_limit[i], 'h014 + 8*i, "RW");
    end

    err_status = switch_err_reg::type_id::create("err_status");
    err_status.acc = "W1C"; err_status.is_vol = 1; err_status.reset_one = 0;
    err_status.configure(this); err_status.build();
    default_map.add_reg(err_status, 'h030, "RW");

    err_mask = switch_err_reg::type_id::create("err_mask");
    err_mask.acc = "RW"; err_mask.is_vol = 0; err_mask.reset_one = 1;
    err_mask.configure(this); err_mask.build();
    default_map.add_reg(err_mask, 'h034, "RW");

    foreach (err_hdr[i]) begin
      err_hdr[i] = switch_ro32_reg::type_id::create($sformatf("err_hdr_src%0d", i+1));
      err_hdr[i].configure(this); err_hdr[i].build();
      default_map.add_reg(err_hdr[i], 'h038 + 4*i, "RO");
    end

    foreach (pkt_cnt[i]) begin
      pkt_cnt[i] = switch_ro32_reg::type_id::create($sformatf("pkt_cnt_src%0d", i+1));
      pkt_cnt[i].configure(this); pkt_cnt[i].build();
      default_map.add_reg(pkt_cnt[i], 'h040 + 4*i, "RO");
    end

    drop_cnt = switch_drop_cnt_reg::type_id::create("drop_cnt");
    drop_cnt.configure(this); drop_cnt.build();
    default_map.add_reg(drop_cnt, 'h048, "RO");

    id_version = switch_id_version_reg::type_id::create("id_version");
    id_version.configure(this); id_version.build();
    default_map.add_reg(id_version, 'h04C, "RO");

    // ERR_STATUS is W1C and changes with traffic: keep it out of bit-bash
    uvm_resource_db#(bit)::set({"REG::", err_status.get_full_name()}, "NO_REG_BIT_BASH_TEST", 1, this);

    lock_model();
  endfunction

endclass : switch_reg_block

`endif
