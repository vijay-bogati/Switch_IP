/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_scoreboard.sv
 Module/class Name             : switch_scoreboard
 Author                        : Vijay Bogati
 Description                   : Cycle-accurate reference model and checker: predicts destination / drop / truncation per packet, compares destination packets, models every CSR (reads and pslverr checked on each APB access) and checks the error pin every clock
***************************************************************/
`ifndef SWITCH_SCOREBOARD_SV
`define SWITCH_SCOREBOARD_SV

//------------------------------------------------------------------
// Ordering inside one clock edge E (all monitors sample just before E):
//   1. APB reads / pslverr are compared against the model state before E
//   2. pending CFG_OVERLAP (range written at E-1) is evaluated
//   3. accepted source beats are run through the ingress model using the
//      configuration before E
//   4. APB writes update the configuration / build the W1C clear mask
//   5. ERR_STATUS = (status & ~clear) | set   (set wins), header capture
//   6. destination packets ending at E are compared
//   7. the error pin (after E) is compared with |(status & mask)
//------------------------------------------------------------------
class switch_scoreboard extends uvm_component;
  `uvm_component_utils(switch_scoreboard)

  uvm_tlm_analysis_fifo #(apb_master_tx) apb_fifo;
  uvm_tlm_analysis_fifo #(stream_beat)   src_fifo  [2];
  uvm_tlm_analysis_fifo #(stream_tx)     dest_fifo [4];

  switch_env_config      cfg;
  virtual switch_ctrl_if vif;
  switch_coverage        cov;

  //---------------- CSR model ----------------
  bit        ctrl_en;
  bit [7:0]  route;
  bit [7:0]  maxp;
  bit [11:0] base  [4];
  bit [11:0] limit [4];
  bit [31:0] err_status;
  bit [31:0] err_mask;
  bit [31:0] err_hdr [2];
  bit [31:0] pkt_cnt [2];
  bit [15:0] drop_cnt[2];
  bit        overlap_pending;

  //---------------- ingress model ----------------
  ing_state_e    st     [2];
  int unsigned   remain [2];
  int            cur_dest[2];
  bit [31:0]     cur_hdr[2];
  switch_exp_pkt cur_pkt[2];

  switch_exp_pkt exp_q [4][2][$];   // expected packets per dest per src
  int            order [4][$];      // observed source order per dest

  //---------------- statistics ----------------
  int unsigned n_hdr      [2];
  int unsigned n_fwd      [2];
  int unsigned n_drop     [2];
  int unsigned n_rx_pkts;
  int unsigned n_rx_beats;
  int unsigned n_apb_rd;
  int unsigned n_apb_wr;
  int unsigned n_set_clr_collision;
  int unsigned n_err_pin_checks;
  int unsigned n_mismatch;

  function new(string name = "switch_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_fifo = new("apb_fifo", this);
    foreach (src_fifo[s])  src_fifo[s]  = new($sformatf("src_fifo%0d", s), this);
    foreach (dest_fifo[d]) dest_fifo[d] = new($sformatf("dest_fifo%0d", d), this);
    if (!uvm_config_db#(switch_env_config)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("NOCFG", "switch_env_config not found")
    vif = cfg.ctrl_vif;
    reset_model();
  endfunction

  //================================================================
  // helpers
  //================================================================
  function void mismatch(string id, string msg);
    n_mismatch++;
    `uvm_error(id, msg)
  endfunction

  function void reset_model();
    ctrl_en  = 0;
    route    = 8'hED;
    maxp     = 8'hFF;
    foreach (base[i]) begin
      base[i]  = 12'(i * 'h100);
      limit[i] = 12'(i * 'h100 + 'hFF);
    end
    err_status      = 0;
    err_mask        = ERR_BITS;
    err_hdr         = '{0, 0};
    pkt_cnt         = '{0, 0};
    drop_cnt        = '{0, 0};
    overlap_pending = 0;
    foreach (st[s]) begin
      st[s]      = ING_IDLE;
      remain[s]  = 0;
      cur_pkt[s] = null;
    end
    for (int d = 0; d < 4; d++) for (int s = 0; s < 2; s++) exp_q[d][s].delete();
    foreach (order[d]) order[d].delete();
  endfunction

  function void flush_fifos();
    apb_fifo.flush();
    foreach (src_fifo[s])  src_fifo[s].flush();
    foreach (dest_fifo[d]) dest_fifo[d].flush();
  endfunction

  function bit mapped(bit [11:0] a);
    a[1:0] = 0;
    return (a inside {CSR_CTRL, CSR_ROUTE_CFG, CSR_MAX_PAYLOAD,
                      [CSR_DEST1_BASE:CSR_DEST4_LIMIT],
                      CSR_ERR_STATUS, CSR_ERR_MASK, CSR_ERR_HDR1, CSR_ERR_HDR2,
                      CSR_PKT_CNT1, CSR_PKT_CNT2, CSR_DROP_CNT, CSR_ID_VERSION});
  endfunction

  function bit [31:0] read_model(bit [11:0] a);
    a[1:0] = 0;
    if (a >= CSR_DEST1_BASE && a <= CSR_DEST4_LIMIT) begin
      int i = (a - CSR_DEST1_BASE) >> 3;
      return a[2] ? {20'b0, limit[i]} : {20'b0, base[i]};
    end
    case (a)
      CSR_CTRL:        return {31'b0, ctrl_en};
      CSR_ROUTE_CFG:   return {24'b0, route};
      CSR_MAX_PAYLOAD: return {24'b0, maxp};
      CSR_ERR_STATUS:  return err_status;
      CSR_ERR_MASK:    return err_mask;
      CSR_ERR_HDR1:    return err_hdr[0];
      CSR_ERR_HDR2:    return err_hdr[1];
      CSR_PKT_CNT1:    return pkt_cnt[0];
      CSR_PKT_CNT2:    return pkt_cnt[1];
      CSR_DROP_CNT:    return {drop_cnt[1], drop_cnt[0]};
      CSR_ID_VERSION:  return ID_VERSION_VAL;
      default:         return 32'h0;
    endcase
  endfunction

  function int decode(bit [11:0] id);
    for (int i = 0; i < 4; i++)
      if (base[i] <= id && id <= limit[i]) return i;
    return 4;   // none
  endfunction

  function bit ranges_overlap();
    for (int a = 0; a < 4; a++)
      for (int b = a + 1; b < 4; b++)
        if (base[a] <= limit[a] && base[b] <= limit[b] &&
            base[a] <= limit[b] && base[b] <= limit[a])
          return 1;
    return 0;
  endfunction

  function bit any_range_disabled();
    foreach (base[i]) if (base[i] > limit[i]) return 1;
    return 0;
  endfunction

  function void count_drop(int s);
    n_drop[s]++;
    if (drop_cnt[s] != 16'hFFFF) drop_cnt[s]++;
  endfunction

  function void sample_pkt(int s, int d, switch_outcome_e oc, bit [7:0] size);
    if (cov != null) cov.cg_pkt.sample(s, d, oc, size);
  endfunction

  //================================================================
  // Ingress model for one accepted beat. Returns the per-source error
  // bits raised by this beat and the header to capture.
  //================================================================
  function void ingress(int s, stream_beat b, output bit [4:0] e, output bit [31:0] eh);
    e  = 0;
    eh = cur_hdr[s];
    if ((st[s] == ING_IDLE) != b.first)
      mismatch("SB_FRAMING", $sformatf("src%0d: monitor/model packet boundary disagree (state %s, first=%0b)",
                                       s+1, st[s].name(), b.first));
    case (st[s])
      ING_IDLE: begin
        bit [3:0]  sid  = b.data[31:28];
        bit [11:0] did  = b.data[27:16];
        bit [7:0]  size = b.data[15:8];
        int        d    = decode(did);
        switch_outcome_e oc;

        if (!ctrl_en)
          mismatch("SB_SWITCH_EN", $sformatf("src%0d: header 0x%08h accepted while CTRL.SWITCH_EN=0", s+1, b.data));

        n_hdr[s]++;
        cur_hdr[s] = b.data;
        eh         = b.data;
        if (cov != null) cov.cg_cfg.sample(ranges_overlap(), any_range_disabled(), maxp, route);

        // checks in spec priority order; first failure only
        if (size == 0 || size > maxp)                 begin oc = OUT_LEN;      e[E_LEN]      = 1; end
        else if (sid != 4'(s + 1))                    begin oc = OUT_SRCID;    e[E_SRCID]    = 1; end
        else if (d == 4)                              begin oc = OUT_UNMAPPED; e[E_UNMAPPED] = 1; end
        else if (!HW_PERM[s][d])                      begin oc = OUT_ILLEGAL;  e[E_ILLEGAL]  = 1; end
        else if (!route[s*4 + d])                     begin oc = OUT_DISABLED; e[E_DISABLED] = 1; end
        else                                          oc = OUT_FWD;

        if (oc != OUT_FWD) begin
          count_drop(s);
          sample_pkt(s, d, oc, size);
          `uvm_info(get_type_name(), $sformatf("src%0d hdr 0x%08h -> DROP (%s)", s+1, b.data, oc.name()), UVM_HIGH)
          st[s] = b.last ? ING_IDLE : ING_DROP;
        end else begin
          cur_pkt[s]          = new();
          cur_pkt[s].src      = s;
          cur_pkt[s].dest     = d;
          cur_pkt[s].beats.push_back(b.data);
          exp_q[d][s].push_back(cur_pkt[s]);
          cur_dest[s] = d;
          `uvm_info(get_type_name(), $sformatf("src%0d hdr 0x%08h -> dest%0d", s+1, b.data, d+1), UVM_HIGH)
          if (b.last) begin
            // last on the header itself: truncated packet
            e[E_LEN] = 1;
            count_drop(s);
            cur_pkt[s].complete = 1;
            sample_pkt(s, d, OUT_EARLY_LAST, size);
            st[s] = ING_IDLE;
          end else begin
            remain[s] = size;
            st[s]     = ING_FWD;
          end
        end
      end

      ING_FWD: begin
        cur_pkt[s].beats.push_back(b.data);
        if (remain[s] == 1) begin
          cur_pkt[s].complete = 1;          // DUT forces last on this beat
          if (b.last) begin
            n_fwd[s]++;
            pkt_cnt[s]++;
            sample_pkt(s, cur_dest[s], OUT_FWD, cur_hdr[s][15:8]);
            st[s] = ING_IDLE;
          end else begin
            e[E_LEN] = 1;
            count_drop(s);
            sample_pkt(s, cur_dest[s], OUT_LATE_LAST, cur_hdr[s][15:8]);
            st[s] = ING_DROP;
          end
        end else if (b.last) begin
          e[E_LEN] = 1;
          count_drop(s);
          cur_pkt[s].complete = 1;
          sample_pkt(s, cur_dest[s], OUT_EARLY_LAST, cur_hdr[s][15:8]);
          st[s] = ING_IDLE;
        end
        remain[s]--;
      end

      ING_DROP: begin
        if (b.last) st[s] = ING_IDLE;
      end
    endcase
  endfunction

  //================================================================
  // APB write -> configuration / W1C clear mask
  //================================================================
  function void apb_write(apb_master_tx t, ref bit [31:0] clr);
    bit [11:0] a = {t.paddr[11:2], 2'b00};
    bit [31:0] m = {{8{t.pstrb[3]}}, {8{t.pstrb[2]}}, {8{t.pstrb[1]}}, {8{t.pstrb[0]}}};
    bit [31:0] w = t.pwdata;
    if (!mapped(a)) return;
    if (a >= CSR_DEST1_BASE && a <= CSR_DEST4_LIMIT) begin
      int i = (a - CSR_DEST1_BASE) >> 3;
      if (a[2]) begin
        if (t.pstrb[0]) limit[i][7:0]  = w[7:0];
        if (t.pstrb[1]) limit[i][11:8] = w[11:8];
      end else begin
        if (t.pstrb[0]) base[i][7:0]   = w[7:0];
        if (t.pstrb[1]) base[i][11:8]  = w[11:8];
      end
      overlap_pending = 1;
      return;
    end
    case (a)
      CSR_CTRL:        if (t.pstrb[0]) ctrl_en = w[0];
      CSR_ROUTE_CFG:   if (t.pstrb[0]) route   = w[7:0] & ROUTE_WMASK;
      CSR_MAX_PAYLOAD: if (t.pstrb[0]) maxp    = w[7:0];
      CSR_ERR_MASK:    err_mask = ((err_mask & ~m) | (w & m)) & ERR_BITS;
      CSR_ERR_STATUS:  clr |= (w & m & ERR_BITS);
      default: ;       // RO: ignored
    endcase
  endfunction

  //================================================================
  // Destination packet compare
  //================================================================
  function void check_dest_pkt(int d, stream_tx p);
    int s;
    switch_exp_pkt e;
    n_rx_pkts++;
    n_rx_beats += p.beats.size();
    s = int'(p.beats[0][31:28]) - 1;
    if (s < 0 || s > 1) begin
      mismatch("SB_DEST_SRCID", $sformatf("dest%0d: packet header 0x%08h has invalid src_id", d+1, p.beats[0]));
      return;
    end
    if (exp_q[d][s].size() == 0) begin
      mismatch("SB_UNEXPECTED", $sformatf("dest%0d: unexpected packet from src%0d, hdr=0x%08h (%0d beats)",
                                          d+1, s+1, p.beats[0], p.beats.size()));
      return;
    end
    e = exp_q[d][s].pop_front();
    if (!e.complete)
      mismatch("SB_EARLY_END", $sformatf("dest%0d: src%0d packet ended after %0d beats before the source packet ended",
                                         d+1, s+1, p.beats.size()));
    if (e.beats.size() != p.beats.size())
      mismatch("SB_LEN", $sformatf("dest%0d src%0d hdr=0x%08h: %0d beats received, %0d expected",
                                   d+1, s+1, e.beats[0], p.beats.size(), e.beats.size()));
    for (int i = 0; i < e.beats.size() && i < p.beats.size(); i++)
      if (e.beats[i] !== p.beats[i]) begin
        mismatch("SB_DATA", $sformatf("dest%0d src%0d beat %0d: 0x%08h received, 0x%08h expected (corruption/interleave)",
                                      d+1, s+1, i, p.beats[i], e.beats[i]));
        break;
      end
    if (cov != null && d >= 2 && order[d].size() != 0)
      cov.cg_arb.sample(d, s, order[d][$]);
    order[d].push_back(s);
  endfunction

  //================================================================
  // Main loop
  //================================================================
  task run_phase(uvm_phase phase);
    forever begin
      time t;
      @(posedge vif.clk);
      t = $time;
      #1;
      if (vif.rst_n !== 1'b1) begin
        reset_model();
        flush_fifos();
        continue;
      end
      process_edge(t);
    end
  endtask

  function void process_edge(time t);
    apb_master_tx apb_q[$];
    stream_beat   beat [2];
    stream_tx     dpkts[4][$];
    bit [31:0]    set = 0;
    bit [31:0]    clr = 0;
    bit [4:0]     e5  [2];
    bit [31:0]    eh  [2];
    bit [31:0]    kept;

    // collect everything sampled at this edge
    begin
      apb_master_tx a;
      stream_beat   b;
      stream_tx     p;
      while (apb_fifo.try_get(a)) apb_q.push_back(a);
      foreach (src_fifo[s]) begin
        beat[s] = null;
        while (src_fifo[s].try_get(b)) begin
          if (b.stamp != t) mismatch("SB_TIME", $sformatf("src%0d beat stamped %0t at edge %0t", s+1, b.stamp, t));
          if (beat[s] != null) mismatch("SB_TIME", $sformatf("src%0d: two beats in one cycle", s+1));
          beat[s] = b;
        end
      end
      foreach (dest_fifo[d])
        while (dest_fifo[d].try_get(p)) dpkts[d].push_back(p);
    end

    // 1. APB reads and responses
    foreach (apb_q[i]) begin
      apb_master_tx a = apb_q[i];
      bit exp_err = !mapped(a.paddr);
      if (a.pslverr !== apb_resp_e'(exp_err))
        mismatch("SB_PSLVERR", $sformatf("APB %s 0x%03h: pslverr=%0b expected %0b",
                                         a.pwrite.name(), a.paddr, a.pslverr, exp_err));
      if (a.pwrite == APB_READ) begin
        bit [31:0] exp = read_model(a.paddr);
        n_apb_rd++;
        if (a.prdata !== exp)
          mismatch("SB_CSR_READ", $sformatf("APB read 0x%03h: 0x%08h, model 0x%08h", a.paddr, a.prdata, exp));
      end else begin
        n_apb_wr++;
      end
    end

    // 2. overlap check one clock after a range write
    if (overlap_pending) begin
      overlap_pending = 0;
      if (ranges_overlap()) set[E_OVERLAP] = 1;
    end

    // 3. source beats with the configuration before this edge
    foreach (beat[s]) begin
      e5[s] = 0;
      eh[s] = 0;
      if (beat[s] != null) ingress(s, beat[s], e5[s], eh[s]);
    end
    set |= {19'b0, e5[1], 3'b0, e5[0]};

    // 4. APB writes
    foreach (apb_q[i])
      if (apb_q[i].pwrite == APB_WRITE) apb_write(apb_q[i], clr);

    // 5. status update: set wins over clear; first-error header capture
    kept = err_status & ~clr;
    if (|e5[0] && !(|kept[4:0]))  err_hdr[0] = eh[0];
    if (|e5[1] && !(|kept[12:8])) err_hdr[1] = eh[1];
    if (set & clr) n_set_clr_collision++;
    if (cov != null) begin
      for (int i = 0; i < 32; i++) begin
        if (set[i]) cov.cg_err_set.sample(i, err_mask[i]);
        if (clr[i] && (err_status[i] || set[i])) cov.cg_err_clr.sample(i, set[i]);   // incl. set-and-clear in one cycle
      end
    end
    err_status = kept | set;

    // 6. destination packets
    for (int d = 0; d < 4; d++) for (int k = 0; k < dpkts[d].size(); k++) check_dest_pkt(d, dpkts[d][k]);

    // 7. error pin
    n_err_pin_checks++;
    if (vif.error !== |(err_status & err_mask))
      mismatch("SB_ERROR_PIN", $sformatf("error pin=%0b, expected %0b (ERR_STATUS=0x%08h ERR_MASK=0x%08h)",
                                         vif.error, |(err_status & err_mask), err_status, err_mask));
  endfunction

  //================================================================
  // Query helpers for sequences
  //================================================================
  function bit is_idle();
    foreach (st[s]) if (st[s] != ING_IDLE) return 0;
    for (int d = 0; d < 4; d++) for (int s = 0; s < 2; s++) if (exp_q[d][s].size() != 0) return 0;
    return 1;
  endfunction

  function int pending_pkts();
    int n = 0;
    for (int d = 0; d < 4; d++) for (int s = 0; s < 2; s++) n += exp_q[d][s].size();
    return n;
  endfunction

  function void check_phase(uvm_phase phase);
    if (!cfg.allow_leftover) begin
      for (int d = 0; d < 4; d++) for (int s = 0; s < 2; s++)
        if (exp_q[d][s].size() != 0)
          mismatch("SB_LEFTOVER", $sformatf("dest%0d: %0d packet(s) from src%0d never arrived",
                                            d+1, exp_q[d][s].size(), s+1));
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf({"\n----------------- Switch scoreboard -----------------\n",
              " headers  src1=%0d src2=%0d\n",
              " fwd      src1=%0d src2=%0d\n",
              " dropped  src1=%0d src2=%0d\n",
              " received %0d packets / %0d beats\n",
              " APB      %0d reads checked, %0d writes\n",
              " error pin checks %0d, set/clear collisions %0d\n",
              " mismatches %0d\n",
              "-----------------------------------------------------"},
              n_hdr[0], n_hdr[1], n_fwd[0], n_fwd[1], n_drop[0], n_drop[1],
              n_rx_pkts, n_rx_beats, n_apb_rd, n_apb_wr,
              n_err_pin_checks, n_set_clr_collision, n_mismatch), UVM_LOW)
  endfunction

endclass : switch_scoreboard

`endif
