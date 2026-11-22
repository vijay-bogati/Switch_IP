/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_system_vseqs.sv
 Module/class Name             : switch_arbitration_vseq, switch_concurrency_vseq, switch_backpressure_vseq, switch_error_pin_vseq, switch_dynamic_cfg_vseq, switch_switch_en_vseq, switch_reset_vseq, switch_drop_cnt_sat_vseq, switch_random_vseq
 Author                        : Vijay Bogati
 Description                   : System-level virtual sequences (spec 9.3: Arbitration, Concurrency, Back-pressure, Error pin, Dynamic config, Reset) plus counter saturation and constrained-random regression traffic
***************************************************************/
`ifndef SWITCH_SYSTEM_VSEQS_SV
`define SWITCH_SYSTEM_VSEQS_SV

//------------------------------------------------------------------
// Round-robin on dest3/dest4: both sources contend, packets alternate
// and never interleave (interleave is caught by the scoreboard)
//------------------------------------------------------------------
class switch_arbitration_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_arbitration_vseq)

  int unsigned n_pkts = 6;

  function new(string name = "switch_arbitration_vseq");
    super.new(name);
  endfunction

  task check_alternate(int d, int from);
    if (sb.order[d].size() - from != 2 * n_pkts)
      `uvm_error("ARB", $sformatf("dest%0d: %0d packets, expected %0d", d+1, sb.order[d].size() - from, 2 * n_pkts))
    for (int i = from + 1; i < sb.order[d].size(); i++)
      if (sb.order[d][i] == sb.order[d][i-1])
        `uvm_error("ARB", $sformatf("dest%0d: packet %0d from src%0d twice in a row under contention",
                                    d+1, i - from, sb.order[d][i] + 1))
  endtask

  task body();
    int from;
    enable_switch();
    // after reset src1 has priority: simultaneous single packets
    from = sb.order[2].size();
    fork
      send(0, 12'h210, 3);
      send(1, 12'h220, 3);
    join
    wait_idle();
    if (sb.order[2][from] != 0) `uvm_error("ARB", "src1 did not win the first arbitration after reset")

    for (int d = 2; d < 4; d++) begin
      from = sb.order[d].size();
      fork
        for (int i = 0; i < n_pkts; i++) send(0, dest_addr(d, 'h10 + i), $urandom_range(1, 12));
        for (int i = 0; i < n_pkts; i++) send(1, dest_addr(d, 'h80 + i), $urandom_range(1, 12));
      join
      wait_idle();
      check_alternate(d, from);
    end

    // contention on both shared destinations at once, with back-pressure
    cfg.set_ready_pct(60);
    fork
      for (int i = 0; i < 20; i++) send(0, dest_addr(2 + (i % 2), i), $urandom_range(1, 8), -1, -1, 10);
      for (int i = 0; i < 20; i++) send(1, dest_addr(2 + ((i + 1) % 2), i), $urandom_range(1, 8), -1, -1, 10);
    join
    wait_idle();
    cfg.set_ready_pct(100);
    reg_chk(ral.err_status, 0, "no errors");
  endtask
endclass

//------------------------------------------------------------------
// Concurrency: independent destinations at full rate (1 beat/clock)
//------------------------------------------------------------------
class switch_concurrency_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_concurrency_vseq)

  function new(string name = "switch_concurrency_vseq");
    super.new(name);
  endfunction

  task run_pair(int d1, int d2, int n, int size);
    time t0, t_end[2];
    int  beats = n * (size + 1);
    t0 = $time;
    fork
      begin for (int i = 0; i < n; i++) send(0, dest_addr(d1, i), size); t_end[0] = $time; end
      begin for (int i = 0; i < n; i++) send(1, dest_addr(d2, i), size); t_end[1] = $time; end
    join
    wait_idle();
    foreach (t_end[s]) begin
      int cycles = (t_end[s] - t0) / 10ns;
      `uvm_info("CONC", $sformatf("src%0d: %0d beats in %0d cycles", s+1, beats, cycles), UVM_LOW)
      if (cycles > beats + 2)
        `uvm_error("CONC", $sformatf("src%0d not at full rate: %0d beats took %0d cycles", s+1, beats, cycles))
    end
  endtask

  task body();
    enable_switch();
    cfg.set_ready_pct(100);
    run_pair(0, 1, 8, 16);     // src1->dest1 with src2->dest2
    run_pair(2, 3, 8, 16);     // src1->dest3 with src2->dest4
    run_pair(3, 2, 8, 16);     // src1->dest4 with src2->dest3
    run_pair(0, 3, 16, 1);     // short packets
    reg_chk(ral.err_status, 0, "no errors");
    check_counters(80, 0);
  endtask
endclass

//------------------------------------------------------------------
// Back-pressure: random destN_ready and random srcN_valid gaps
//------------------------------------------------------------------
class switch_backpressure_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_backpressure_vseq)

  function new(string name = "switch_backpressure_vseq");
    super.new(name);
  endfunction

  task body();
    int pct[5] = '{10, 30, 50, 80, 100};
    enable_switch();
    foreach (pct[k]) begin
      foreach (cfg.dest_cfg[d]) cfg.dest_cfg[d].ready_pct = (k == 4) ? $urandom_range(5, 100) : pct[k];
      `uvm_info("BP", $sformatf("ready_pct = %0d / %0d / %0d / %0d", cfg.dest_cfg[0].ready_pct,
                cfg.dest_cfg[1].ready_pct, cfg.dest_cfg[2].ready_pct, cfg.dest_cfg[3].ready_pct), UVM_LOW)
      fork
        send_rand(0, 25, 30, 24, 0);
        send_rand(1, 25, 30, 24, 0);
      join
      wait_idle();
    end
    cfg.set_ready_pct(100);
    reg_chk(ral.err_status, 0, "no errors");
    check_counters(250, 0);
  endtask
endclass

//------------------------------------------------------------------
// Error pin: mask/unmask, W1C, set-and-clear in the same cycle,
// ERR_HDR capture of the first error only
//------------------------------------------------------------------
class switch_error_pin_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_error_pin_vseq)

  function new(string name = "switch_error_pin_vseq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] h_first = {4'h1, 12'h150, 8'd1, 8'h0};
    enable_switch();
    check_pin(0, "after reset");

    // masked error: status set, pin stays low
    reg_wr(ral.err_mask, 32'h0000_1F00);
    send(0, 12'h150, 1);                       // src1 ILLEGAL (masked)
    wait_idle();
    wait_cycles(2);
    check_pin(0, "masked error");
    reg_chk(ral.err_hdr[0], h_first, "capture with masked bit");
    // unmasking an already-set bit raises the pin
    reg_wr(ral.err_mask, 32'h0001_1F1F);
    check_pin(1, "unmasking a set bit");

    // later errors of the same source do not overwrite the capture
    send(0, 12'h900, 2);                       // UNMAPPED
    send(0, 12'h010, 0, 1);                    // LEN
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_ILLEGAL) | ebit(0, E_UNMAPPED) | ebit(0, E_LEN), "sticky bits");
    reg_chk(ral.err_hdr[0], h_first, "capture not overwritten");

    // partial clear: pin stays high while any unmasked bit remains
    reg_wr(ral.err_status, ebit(0, E_ILLEGAL) | ebit(0, E_UNMAPPED));
    check_pin(1, "bit still set after partial clear");
    reg_wr(ral.err_status, ebit(0, E_LEN));
    check_pin(0, "last bit cleared");
    // after clearing, the next error is captured again
    send(0, 12'h020, 3, -1, 9);                // SRCID
    wait_idle();
    reg_chk(ral.err_hdr[0], {4'h9, 12'h020, 8'd3, 8'h0}, "recapture after clear");
    clear_errors();

    // set-and-clear in the same cycle: sweep the relative timing
    begin
      int unsigned coll0 = sb.n_set_clr_collision;
      for (int off = 0; off < 10; off++) begin
        fork
          begin wait_cycles(off); send(1, 12'h050, 1, 0); end   // src2 ILLEGAL, header only
          reg_wr(ral.err_status, ebit(1, E_ILLEGAL));
        join
        wait_idle();
        clear_errors();
      end
      if (sb.n_set_clr_collision == coll0)
        `uvm_error("ERRPIN", "set-and-clear collision never hit by the timing sweep")
      else
        `uvm_info("ERRPIN", $sformatf("%0d set/clear collisions checked", sb.n_set_clr_collision - coll0), UVM_LOW)
    end

    // every error bit through the pin, one at a time
    begin
      bit [31:0] exp;
      for (int s = 0; s < 2; s++) begin
        send(s, (s == 0) ? 12'h150 : 12'h050, 1);            exp |= ebit(s, E_ILLEGAL);
        reg_wr(ral.route_cfg, ROUTE_WMASK & ~(8'h4 << (4*s)));
        send(s, 12'h210, 1);                                  exp |= ebit(s, E_DISABLED);
        reg_wr(ral.route_cfg, ROUTE_WMASK);
        send(s, 12'h800, 1);                                  exp |= ebit(s, E_UNMAPPED);
        send(s, 12'h210, 1, -1, 0);                           exp |= ebit(s, E_SRCID);
        send(s, 12'h210, 0, 0);                               exp |= ebit(s, E_LEN);
      end
      wait_idle();
      reg_chk(ral.err_status, exp, "all source error bits");
      for (int i = 0; i < 32; i++) begin
        if (!exp[i]) continue;
        reg_wr(ral.err_status, 32'h1 << i);
        exp[i] = 0;
        check_pin(exp != 0, $sformatf("after clearing bit %0d", i));
      end
    end
  endtask
endclass

//------------------------------------------------------------------
// ROUTE_CFG / range changes mid-packet take effect at the next header
//------------------------------------------------------------------
class switch_dynamic_cfg_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_dynamic_cfg_vseq)

  function new(string name = "switch_dynamic_cfg_vseq");
    super.new(name);
  endfunction

  task body();
    enable_switch();
    cfg.set_ready_pct(40);
    // disable the route and move the range while a long packet is in flight
    fork
      send(0, 12'h060, 120, -1, -1, 20);
      begin
        wait_cycles(15);
        reg_wr(ral.route_cfg, ROUTE_WMASK & ~8'h01);    // src1->dest1 off
        reg_wr(ral.dest_limit[0], 'h010);               // dest1 shrinks
        reg_wr(ral.max_payload, 8);                      // smaller max
      end
    join
    wait_idle();
    reg_chk(ral.err_status, 0, "in-flight packet unaffected");
    // next headers use the new configuration
    send(0, 12'h005, 2);                                 // ROUTE_DISABLED
    send(0, 12'h060, 2);                                 // now unmapped
    send(1, 12'h105, 9);                                 // > MAX_PAYLOAD
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_DISABLED) | ebit(0, E_UNMAPPED) | ebit(1, E_LEN), "new config");
    reg_chk(ral.err_hdr[0], {4'h1, 12'h005, 8'd2, 8'h0}, "first src1 error");
    // retarget a shared destination mid-packet
    reg_wr(ral.route_cfg, ROUTE_WMASK);
    reg_wr(ral.dest_limit[0], 'h0FF);
    reg_wr(ral.max_payload, 255);
    clear_errors();
    fork
      send(1, 12'h250, 60, -1, -1, 10);
      begin
        wait_cycles(10);
        reg_wr(ral.dest_base[2], 'h300); reg_wr(ral.dest_limit[2], 'h300);   // dest3 shrinks (overlaps dest4)
      end
    join
    send(1, 12'h250, 3);                                 // unmapped now
    wait_idle();
    reg_chk(ral.err_status, ebit(1, E_UNMAPPED) | (32'h1 << E_OVERLAP), "range change");
    cfg.set_ready_pct(100);
  endtask
endclass

//------------------------------------------------------------------
// CTRL.SWITCH_EN: sources held off when 0; in-flight packet completes
//------------------------------------------------------------------
class switch_switch_en_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_switch_en_vseq)

  function new(string name = "switch_switch_en_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned h0;
    // switch disabled after reset: header must not be accepted
    h0 = sb.n_hdr[0] + sb.n_hdr[1];
    fork
      begin
        send(0, 12'h030, 4);
        send(1, 12'h130, 4);
      end
      begin
        wait_cycles(50);
        if (sb.n_hdr[0] + sb.n_hdr[1] != h0)
          `uvm_error("SW_EN", "header accepted while SWITCH_EN = 0")
        enable_switch();
      end
    join
    wait_idle();
    check_counters(2, 0);

    // disable in the middle of a packet: it completes, the next one waits
    fork
      begin
        send(0, 12'h040, 40);
        send(0, 12'h041, 2);
      end
      begin
        wait_cycles(10);
        enable_switch(0);
        h0 = sb.n_hdr[0];
        wait_cycles(80);
        if (sb.n_hdr[0] != h0) `uvm_error("SW_EN", "new header accepted after SWITCH_EN cleared")
        if (sb.pending_pkts() != 0) `uvm_error("SW_EN", "in-flight packet did not complete")
        enable_switch(1);
      end
    join
    wait_idle();
    check_counters(4, 0);
  endtask
endclass

//------------------------------------------------------------------
// Reset in the middle of packets
//------------------------------------------------------------------
class switch_reset_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_reset_vseq)

  function new(string name = "switch_reset_vseq");
    super.new(name);
  endfunction

  task body();
    for (int iter = 0; iter < 3; iter++) begin
      enable_switch();
      reg_wr(ral.max_payload, 200);
      reg_wr(ral.route_cfg, 8'h6C);
      cfg.set_ready_pct(50);
      send(0, 12'h150, 1);                            // leave an error pending
      fork
        send(0, 12'h370, 100);                      // src1 -> dest4 (enabled in 0x6C)
        send(1, 12'h270, 100);                      // src2 -> dest3
        begin
          wait_cycles(30 + 17 * iter);
          vif.assert_reset_async(3 + iter);
        end
      join
      // outputs during reset
      #1;
      if (vif.error !== 0) `uvm_error("RST", "error pin not 0 in reset")
      wait_cycles(3);
      vif.release_reset();
      ral.reset();
      cfg.set_ready_pct(100);

      // every CSR back to reset value
      reg_chk(ral.ctrl,        0,     "after reset");
      reg_chk(ral.route_cfg,   'hED,  "after reset");
      reg_chk(ral.max_payload, 'hFF,  "after reset");
      reg_chk(ral.err_status,  0,     "after reset");
      reg_chk(ral.pkt_cnt[0],  0,     "after reset");
      reg_chk(ral.drop_cnt,    0,     "after reset");

      // traffic flows again, arbiters back to src1 priority
      enable_switch();
      fork
        send(0, 12'h270, 3);
        send(1, 12'h271, 3);
      join
      wait_idle();
      if (sb.order[2].size() == 0 || sb.order[2][0] != 0)
        `uvm_error("RST", "src1 did not win the first dest3 arbitration after reset")
      check_counters(2, 0);
    end
  endtask
endclass

//------------------------------------------------------------------
// DROP_CNT saturates at 0xFFFF per source
//------------------------------------------------------------------
class switch_drop_cnt_sat_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_drop_cnt_sat_vseq)

  function new(string name = "switch_drop_cnt_sat_vseq");
    super.new(name);
  endfunction

  task body();
    enable_switch();
    reg_wr(ral.err_mask, 0);
    // 65537 header-only drops on src1 (ILLEGAL), 3 on src2
    fork
      for (int i = 0; i < 65537; i++) send(0, 12'h150, 1, 0);
      for (int i = 0; i < 3; i++)     send(1, 12'h050, 1, 0);
    join
    wait_idle();
    reg_chk(ral.drop_cnt, {16'd3, 16'hFFFF}, "src1 saturated, src2 counting");
    send(0, 12'h150, 1, 0);
    wait_idle();
    reg_chk(ral.drop_cnt, {16'd3, 16'hFFFF}, "stays saturated");
    // now saturate src2 as well
    for (int i = 0; i < 65535; i++) send(1, 12'h050, 1, 0);
    wait_idle();
    reg_chk(ral.drop_cnt, 32'hFFFF_FFFF, "both saturated");
    reg_chk(ral.pkt_cnt[0], 0, "no forwarded packets");
  endtask
endclass

//------------------------------------------------------------------
// Constrained random: random configuration epochs, random traffic with
// defects, random back-pressure, periodic status reads and clears
//------------------------------------------------------------------
class switch_random_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_random_vseq)

  int unsigned n_epochs = 6;
  int unsigned n_pkts   = 60;

  function new(string name = "switch_random_vseq");
    super.new(name);
  endfunction

  task randomize_config(int epoch);
    uvm_reg_data_t v;
    if (epoch == 0) return;                          // first epoch: defaults
    reg_wr(ral.route_cfg,   ($urandom_range(99) < 70) ? ROUTE_WMASK : ($urandom & ROUTE_WMASK));
    reg_wr(ral.max_payload, ($urandom_range(99) < 50) ? 255 : $urandom_range(1, 40));
    reg_wr(ral.err_mask,    $urandom & ERR_BITS);
    if ($urandom_range(99) < 50) begin
      // permuted, possibly resized / overlapping / disabled ranges
      for (int d = 0; d < 4; d++) begin
        bit [11:0] b = $urandom_range(0, 'hE00);
        bit [11:0] l = b + $urandom_range(0, 'h1FF);
        if ($urandom_range(99) < 10) l = b - 1;         // disabled range
        reg_wr(ral.dest_base[d], b);
        reg_wr(ral.dest_limit[d], l);
      end
    end else begin
      for (int d = 0; d < 4; d++) begin
        reg_wr(ral.dest_base[d],  d * 'h100);
        reg_wr(ral.dest_limit[d], d * 'h100 + 'hFF);
      end
    end
  endtask

  task body();
    enable_switch();
    for (int e = 0; e < n_epochs; e++) begin
      `uvm_info("RAND", $sformatf("epoch %0d", e), UVM_LOW)
      randomize_config(e);
      foreach (cfg.dest_cfg[d]) cfg.dest_cfg[d].ready_pct = $urandom_range(20, 100);
      fork
        send_rand(0, n_pkts, $urandom_range(0, 40), 40, 15);
        send_rand(1, n_pkts, $urandom_range(0, 40), 40, 15);
        // CSR traffic in parallel (reads are checked by the scoreboard)
        begin
          uvm_reg_data_t v;
          repeat (20) begin
            wait_cycles($urandom_range(20, 200));
            case ($urandom_range(5))
              0: reg_rd(ral.err_status, v);
              1: reg_rd(ral.drop_cnt, v);
              2: reg_rd(ral.pkt_cnt[$urandom_range(1)], v);
              3: reg_rd(ral.err_hdr[$urandom_range(1)], v);
              4: reg_wr(ral.err_status, $urandom & ERR_BITS);
              5: reg_wr(ral.err_mask,   $urandom & ERR_BITS);
            endcase
          end
        end
      join
      wait_idle();
      clear_errors();
    end
    cfg.set_ready_pct(100);
  endtask
endclass

`endif
