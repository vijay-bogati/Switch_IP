/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_reg_vseqs.sv
 Module/class Name             : switch_reg_hw_reset_vseq, switch_reg_bit_bash_vseq, switch_csr_access_vseq
 Author                        : Vijay Bogati
 Description                   : CSR virtual sequences: RAL reset check, RAL bit-bash, and directed access-type checks (tied bits, pstrb, RO, W1C, unmapped pslverr)
***************************************************************/
`ifndef SWITCH_REG_VSEQS_SV
`define SWITCH_REG_VSEQS_SV

//------------------------------------------------------------------
// Reset values of every register (spec 6 / 9.3 CSR)
//------------------------------------------------------------------
class switch_reg_hw_reset_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_reg_hw_reset_vseq)

  function new(string name = "switch_reg_hw_reset_vseq");
    super.new(name);
  endfunction

  task body();
    uvm_reg_hw_reset_seq rst_seq = uvm_reg_hw_reset_seq::type_id::create("rst_seq");
    rst_seq.model = ral;
    rst_seq.start(null, this);

    // volatile registers are skipped by the built-in sequence: check explicitly
    reg_chk(ral.err_status, 32'h0, "reset");
    reg_chk(ral.err_hdr[0], 32'h0, "reset");
    reg_chk(ral.err_hdr[1], 32'h0, "reset");
    reg_chk(ral.pkt_cnt[0], 32'h0, "reset");
    reg_chk(ral.pkt_cnt[1], 32'h0, "reset");
    reg_chk(ral.drop_cnt,   32'h0, "reset");
    reg_chk(ral.ctrl,        32'h0,         "reset");
    reg_chk(ral.route_cfg,   32'hED,        "reset");
    reg_chk(ral.max_payload, 32'hFF,        "reset");
    reg_chk(ral.err_mask,    32'h0001_1F1F, "reset");
    reg_chk(ral.id_version,  32'h5357_0100, "reset");
    foreach (ral.dest_base[i]) begin
      reg_chk(ral.dest_base[i],  i * 'h100,        "reset");
      reg_chk(ral.dest_limit[i], i * 'h100 + 'hFF, "reset");
    end
  endtask
endclass

//------------------------------------------------------------------
// Bit-bash all non-volatile registers through the RAL
//------------------------------------------------------------------
class switch_reg_bit_bash_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_reg_bit_bash_vseq)

  function new(string name = "switch_reg_bit_bash_vseq");
    super.new(name);
  endfunction

  task body();
    uvm_reg_bit_bash_seq bb = uvm_reg_bit_bash_seq::type_id::create("bb");
    bb.model = ral;
    bb.start(null, this);
  endtask
endclass

//------------------------------------------------------------------
// Directed access-type checks
//------------------------------------------------------------------
class switch_csr_access_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_csr_access_vseq)

  bit [11:0] unmapped[] = '{12'h00C, 12'h050, 12'h100, 12'h7FC, 12'hFFC};

  function new(string name = "switch_csr_access_vseq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] rd;
    apb_resp_e rsp;

    // RW full writes / read back, upper bits read as 0
    reg_wr(ral.ctrl, 32'hFFFF_FFFF);         reg_chk(ral.ctrl, 32'h1, "RW upper bits");
    reg_wr(ral.ctrl, 0);
    reg_wr(ral.max_payload, 32'hFFFF_FF3C);  reg_chk(ral.max_payload, 32'h3C, "RW upper bits");
    reg_wr(ral.dest_base[2], 32'hFFFF_FABC); reg_chk(ral.dest_base[2], 32'hABC, "RW upper bits");
    reg_wr(ral.dest_base[2], 'h200);
    reg_wr(ral.max_payload, 'hFF);

    // ROUTE_CFG tied-0 bits
    reg_wr(ral.route_cfg, 32'hFF);           reg_chk(ral.route_cfg, 32'hED, "tied-0 bits");
    reg_wr(ral.route_cfg, 32'h00);           reg_chk(ral.route_cfg, 32'h00, "all off");
    reg_wr(ral.route_cfg, 32'hED);

    // ERR_MASK implemented bits only
    reg_wr(ral.err_mask, 32'hFFFF_FFFF);     reg_chk(ral.err_mask, 32'h0001_1F1F, "implemented bits");
    reg_wr(ral.err_mask, 32'h0);             reg_chk(ral.err_mask, 32'h0, "cleared");
    reg_wr(ral.err_mask, 32'h0001_1F1F);

    // pstrb: byte lanes on 12-bit address registers
    apb_raw(12'h014, APB_WRITE, 32'h0000_0A55, 4'b0010, rd, rsp);   // only [11:8]
    reg_chk(ral.dest_limit[0], 32'h0AFF, "pstrb=0010");
    apb_raw(12'h014, APB_WRITE, 32'h0000_0F11, 4'b0001, rd, rsp);   // only [7:0]
    reg_chk(ral.dest_limit[0], 32'h0A11, "pstrb=0001");
    apb_raw(12'h014, APB_WRITE, 32'h0000_00FF, 4'b0000, rd, rsp);   // no lanes
    reg_chk(ral.dest_limit[0], 32'h0A11, "pstrb=0000");
    reg_wr(ral.dest_limit[0], 'h0FF);
    apb_raw(12'h018, APB_WRITE, 32'h0000_0F80, 4'b0001, rd, rsp);   // DEST2_BASE byte 0 only
    reg_chk(ral.dest_base[1], 32'h0180, "BASE pstrb=0001");
    apb_raw(12'h018, APB_WRITE, 32'h0000_0E00, 4'b0010, rd, rsp);   // byte 1 only
    reg_chk(ral.dest_base[1], 32'h0E80, "BASE pstrb=0010");
    reg_wr(ral.dest_base[1], 'h100);
    apb_raw(CSR_CTRL, APB_WRITE, 32'h0000_0001, 4'b1110, rd, rsp);
    reg_chk(ral.ctrl, 32'h0, "CTRL without byte 0");
    apb_raw(CSR_ROUTE_CFG, APB_WRITE, 32'h0000_0000, 4'b1110, rd, rsp);
    reg_chk(ral.route_cfg, 32'hED, "ROUTE_CFG without byte 0");
    apb_raw(CSR_MAX_PAYLOAD, APB_WRITE, 32'h0000_0010, 4'b1110, rd, rsp);
    reg_chk(ral.max_payload, 32'hFF, "pstrb without byte 0");
    apb_raw(CSR_ERR_MASK, APB_WRITE, 32'h0000_0000, 4'b0010, rd, rsp);
    reg_chk(ral.err_mask, 32'h0001_001F, "pstrb byte 1 cleared src2 mask");
    reg_wr(ral.err_mask, 32'h0001_1F1F);
    apb_raw(CSR_ERR_MASK, APB_WRITE, 32'h0000_0000, 4'b0100, rd, rsp);   // byte 2: CFG_OVERLAP mask
    reg_chk(ral.err_mask, 32'h0000_1F1F, "pstrb byte 2 cleared overlap mask");
    apb_raw(CSR_ERR_MASK, APB_WRITE, 32'h0000_0000, 4'b1000, rd, rsp);   // byte 3: no bits
    reg_chk(ral.err_mask, 32'h0000_1F1F, "pstrb byte 3 no effect");
    reg_wr(ral.err_mask, 32'h0001_1F1F);

    // RO writes ignored without pslverr
    apb_raw(CSR_ID_VERSION, APB_WRITE, 32'h1234_5678, 4'hF, rd, rsp);
    if (rsp != APB_OKAY) `uvm_error("CSR", "pslverr on RO write")
    reg_chk(ral.id_version, 32'h5357_0100, "after write");
    apb_raw(CSR_PKT_CNT1, APB_WRITE, 32'hFFFF_FFFF, 4'hF, rd, rsp);
    reg_chk(ral.pkt_cnt[0], 32'h0, "after write");
    apb_raw(CSR_DROP_CNT, APB_WRITE, 32'hFFFF_FFFF, 4'hF, rd, rsp);
    reg_chk(ral.drop_cnt, 32'h0, "after write");
    apb_raw(CSR_ERR_HDR1, APB_WRITE, 32'hFFFF_FFFF, 4'hF, rd, rsp);
    reg_chk(ral.err_hdr[0], 32'h0, "after write");

    // unmapped offsets: pslverr, read data 0, writes ignored
    foreach (unmapped[i]) begin
      apb_raw(unmapped[i], APB_WRITE, 32'hFFFF_FFFF, 4'hF, rd, rsp);
      if (rsp != APB_SLVERR) `uvm_error("CSR", $sformatf("no pslverr on write to unmapped 0x%03h", unmapped[i]))
      apb_raw(unmapped[i], APB_READ, 0, 0, rd, rsp);
      if (rsp != APB_SLVERR) `uvm_error("CSR", $sformatf("no pslverr on read of unmapped 0x%03h", unmapped[i]))
      if (rd != 0)           `uvm_error("CSR", $sformatf("unmapped 0x%03h read 0x%08h", unmapped[i], rd))
    end
    reg_chk(ral.ctrl, 32'h0, "after unmapped writes");

    // the pstrb writes above widened DEST1 (0x000..0xAFF) and legitimately
    // raised CFG_OVERLAP: check it, then start the W1C part from a clean status
    reg_chk(ral.err_status, 32'h1 << E_OVERLAP, "overlap from pstrb range writes");
    clear_errors();

    // W1C: writing 0 keeps a bit, writing 1 clears it
    enable_switch();
    send(0, 12'h150, 1);                          // src1 -> dest2: ILLEGAL
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_ILLEGAL), "error set");
    reg_wr(ral.err_status, 32'h0);
    reg_chk(ral.err_status, ebit(0, E_ILLEGAL), "W1C write 0 keeps");
    reg_wr(ral.err_status, ~ebit(0, E_ILLEGAL));
    reg_chk(ral.err_status, ebit(0, E_ILLEGAL), "W1C other bits keep");
    reg_wr(ral.err_status, ebit(0, E_ILLEGAL));
    reg_chk(ral.err_status, 32'h0, "W1C write 1 clears");
  endtask
endclass

`endif
