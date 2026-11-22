/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_base_vseq.sv
 Module/class Name             : switch_base_vseq
 Author                        : Vijay Bogati
 Description                   : Base virtual sequence: packet, RAL and raw APB helpers, idle wait; default body is a smoke test over every legal route
***************************************************************/
`ifndef SWITCH_BASE_VSEQ_SV
`define SWITCH_BASE_VSEQ_SV

class switch_base_vseq extends uvm_sequence;
  `uvm_object_utils(switch_base_vseq)
  `uvm_declare_p_sequencer(switch_virtual_sequencer)

  switch_reg_block       ral;
  switch_scoreboard      sb;
  switch_env_config      cfg;
  virtual switch_ctrl_if vif;

  function new(string name = "switch_base_vseq");
    super.new(name);
  endfunction

  task pre_body();
    ral = p_sequencer.ral;
    sb  = p_sequencer.sb;
    cfg = p_sequencer.cfg;
    vif = p_sequencer.ctrl_vif;
  endtask

  // default body: smoke test
  task body();
    enable_switch();
    for (int d = 0; d < 4; d++)
      for (int s = 0; s < 2; s++)
        if (HW_PERM[s][d]) send(s, dest_addr(d, 'h10), 4);
    wait_idle();
    check_counters(6, 0);
  endtask

  //================================================================
  // packet helpers
  //================================================================
  function bit [11:0] dest_addr(int d, int unsigned offset);
    return 12'(d * 'h100 + offset);
  endfunction

  // Send one packet on source s. nbeats < 0: well formed (= size).
  // src_id < 0: correct id for the port.
  task send(int s, int dest_id, int size, int nbeats = -1, int src_id = -1, int unsigned gap_pct = 0);
    stream_pkt_seq seq = stream_pkt_seq::type_id::create($sformatf("pkt_s%0d", s));
    seq.src_id       = (src_id < 0) ? s + 1 : src_id;
    seq.dest_id      = dest_id;
    seq.payload_size = size;
    seq.num_beats    = (nbeats < 0) ? size : nbeats;
    seq.gap_pct      = gap_pct;
    seq.start(p_sequencer.src_sqr[s]);
  endtask

  // Configuration template for kind-mode packets on source s, taken from
  // the RAL mirror (kept up to date by the predictor on every APB access).
  function stream_tx kind_cfg(int s);
    stream_tx t = stream_tx::type_id::create("kind_cfg");
    uvm_reg_data_t route = ral.route_cfg.get_mirrored_value();
    t.port        = s + 1;
    t.hw_perm     = HW_PERM[s];
    t.route_en    = route[s*4 +: 4];
    t.max_payload = ral.max_payload.get_mirrored_value();
    foreach (t.base[d]) begin
      t.base[d]  = ral.dest_base[d].get_mirrored_value();
      t.limit[d] = ral.dest_limit[d].get_mirrored_value();
    end
    return t;
  endfunction

  // One packet of a given kind on source s, fields randomised within the
  // current configuration.
  task send_kind(int s, pkt_kind_e kind, int max_size = 255, int unsigned gap_pct = 0);
    stream_pkt_seq seq = stream_pkt_seq::type_id::create($sformatf("kind_s%0d", s));
    seq.use_kind = 1;
    seq.kind     = kind;
    seq.max_size = max_size;
    seq.gap_pct  = gap_pct;
    seq.cfg_tmpl = kind_cfg(s);
    seq.start(p_sequencer.src_sqr[s]);
  endtask

  // n random packets on source s
  //   err_pct : % of packets of a random error kind (SRCID, UNMAPPED,
  //             ILLEGAL, DISABLED, LEN_ZERO, LEN_OVER, EARLY/LATE last);
  //             kinds impossible in the current configuration are skipped
  //             by the solver. The configuration is re-read per packet.
  task send_rand(int s, int n, int unsigned gap_pct = 10, int max_size = 32, int unsigned err_pct = 10);
    for (int i = 0; i < n; i++) begin
      stream_pkt_seq seq = stream_pkt_seq::type_id::create($sformatf("rnd_s%0d", s));
      seq.use_kind = 1;
      seq.good_pct = 100 - err_pct;
      seq.max_size = max_size;
      seq.gap_pct  = gap_pct;
      seq.cfg_tmpl = kind_cfg(s);
      seq.start(p_sequencer.src_sqr[s]);
    end
  endtask

  //================================================================
  // register helpers
  //================================================================
  task reg_wr(uvm_reg r, uvm_reg_data_t v);
    uvm_status_e st;
    r.write(st, v, .parent(this));
    if (st != UVM_IS_OK) `uvm_error("REG_WR", $sformatf("write %s failed", r.get_name()))
  endtask

  task reg_rd(uvm_reg r, output uvm_reg_data_t v);
    uvm_status_e st;
    r.read(st, v, .parent(this));
    if (st != UVM_IS_OK) `uvm_error("REG_RD", $sformatf("read %s failed", r.get_name()))
  endtask

  // directed expectation (the scoreboard also checks every read)
  task reg_chk(uvm_reg r, uvm_reg_data_t exp, string what = "");
    uvm_reg_data_t v;
    reg_rd(r, v);
    if (v !== exp)
      `uvm_error("REG_CHK", $sformatf("%s %s: read 0x%08h expected 0x%08h", r.get_name(), what, v, exp))
    else
      `uvm_info("REG_CHK", $sformatf("%s %s = 0x%08h OK", r.get_name(), what, v), UVM_MEDIUM)
  endtask

  task apb_raw(bit [11:0] addr, apb_dir_e dir, bit [31:0] wdata, bit [3:0] strb,
               output bit [31:0] rdata, output apb_resp_e resp);
    apb_master_rw_seq seq = apb_master_rw_seq::type_id::create("apb_raw");
    seq.addr  = addr;
    seq.dir   = dir;
    seq.wdata = wdata;
    seq.strb  = strb;
    seq.start(p_sequencer.apb_sqr, this);
    rdata = seq.rdata;
    resp  = seq.resp;
  endtask

  task enable_switch(bit en = 1);
    reg_wr(ral.ctrl, en);
  endtask

  task clear_errors();
    reg_wr(ral.err_status, 32'hFFFF_FFFF);
  endtask

  // expected ERR_STATUS bit for source s
  function bit [31:0] ebit(int s, int e);
    return 32'h1 << (s * 8 + e);
  endfunction

  task check_counters(int fwd_total, int drop_total);
    uvm_reg_data_t p1, p2, dc;
    reg_rd(ral.pkt_cnt[0], p1);
    reg_rd(ral.pkt_cnt[1], p2);
    reg_rd(ral.drop_cnt, dc);
    if (fwd_total >= 0 && p1 + p2 != fwd_total)
      `uvm_error("CNT", $sformatf("PKT_CNT total %0d, expected %0d", p1 + p2, fwd_total))
    if (drop_total >= 0 && dc[15:0] + dc[31:16] != drop_total)
      `uvm_error("CNT", $sformatf("DROP_CNT total %0d, expected %0d", dc[15:0] + dc[31:16], drop_total))
  endtask

  // error pin, checked just after the register update has settled
  task check_pin(bit exp, string what);
    #2ns;
    if (vif.error !== exp)
      `uvm_error("ERRPIN", $sformatf("error pin = %0b, expected %0b: %s", vif.error, exp, what))
  endtask

  //================================================================
  // timing helpers
  //================================================================
  task wait_cycles(int unsigned n);
    vif.wait_cycles(n);
  endtask

  // wait until every expected packet has been delivered and both
  // ingress models are idle
  task wait_idle(int unsigned timeout = 50000);
    int unsigned n = 0, quiet = 0;
    while (quiet < 4) begin
      @(posedge vif.clk);
      quiet = sb.is_idle() ? quiet + 1 : 0;
      if (++n > timeout) begin
        `uvm_error("WAIT_IDLE", $sformatf("timeout: %0d packet(s) still expected", sb.pending_pkts()))
        return;
      end
    end
  endtask

endclass : switch_base_vseq

`endif
