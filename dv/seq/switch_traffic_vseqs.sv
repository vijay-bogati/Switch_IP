/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_traffic_vseqs.sv
 Module/class Name             : switch_routing_vseq, switch_permission_vseq, switch_route_disable_vseq, switch_addr_map_vseq, switch_packet_len_vseq, switch_pkt_kind_vseq
 Author                        : Vijay Bogati
 Description                   : Routing / decode / permission / length virtual sequences (spec 9.3: Routing, Permission, Software enable, Address, Packet)
***************************************************************/
`ifndef SWITCH_TRAFFIC_VSEQS_SV
`define SWITCH_TRAFFIC_VSEQS_SV

//------------------------------------------------------------------
// Every legal route at range base, middle and limit; payload 1..255
//------------------------------------------------------------------
class switch_routing_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_routing_vseq)

  function new(string name = "switch_routing_vseq");
    super.new(name);
  endfunction

  task body();
    int n = 0;
    int offs[3]  = '{'h00, 'h80, 'hFF};
    int sizes[3] = '{1, 17, 255};
    enable_switch();
    for (int d = 0; d < 4; d++)
      for (int s = 0; s < 2; s++) begin
        if (!HW_PERM[s][d]) continue;
        foreach (offs[k]) begin
          send(s, dest_addr(d, offs[k]), sizes[k]);
          n++;
        end
      end
    wait_idle();
    reg_chk(ral.err_status, 0, "no errors on legal routes");
    check_counters(n, 0);
    reg_chk(ral.pkt_cnt[0], 9, "src1 forwarded");
    reg_chk(ral.pkt_cnt[1], 9, "src2 forwarded");
  endtask
endclass

//------------------------------------------------------------------
// Hardware-forbidden routes: src1 -> dest2, src2 -> dest1
//------------------------------------------------------------------
class switch_permission_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_permission_vseq)

  function new(string name = "switch_permission_vseq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] h1 = {4'h1, 12'h100, 8'd3, 8'h00};
    bit [31:0] h2 = {4'h2, 12'h0FF, 8'd2, 8'h00};
    enable_switch();
    send(0, 12'h100, 3);
    send(0, 12'h180, 5);
    send(0, 12'h1FF, 1);
    send(1, 12'h0FF, 2);
    send(1, 12'h000, 4);
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_ILLEGAL) | ebit(1, E_ILLEGAL), "ILLEGAL_ROUTE");
    reg_chk(ral.err_hdr[0], h1, "first src1 error header");
    reg_chk(ral.err_hdr[1], h2, "first src2 error header");
    reg_chk(ral.drop_cnt, {16'd2, 16'd3}, "drops");
    check_counters(0, 5);
    // ROUTE_CFG cannot override the hardware matrix (bits tied to 0)
    reg_wr(ral.route_cfg, 32'hFF);
    clear_errors();
    send(0, 12'h120, 2);
    send(1, 12'h020, 2);
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_ILLEGAL) | ebit(1, E_ILLEGAL), "still ILLEGAL with ROUTE_CFG=FF");
    // legal traffic still flows
    send(0, 12'h020, 2);
    send(1, 12'h120, 2);
    wait_idle();
    check_counters(2, 7);
    reg_wr(ral.route_cfg, 32'hED);
  endtask
endclass

//------------------------------------------------------------------
// Clear each ROUTE_CFG bit: ROUTE_DISABLED; re-enable and resend
//------------------------------------------------------------------
class switch_route_disable_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_route_disable_vseq)

  function new(string name = "switch_route_disable_vseq");
    super.new(name);
  endfunction

  task body();
    int fwd = 0, drop = 0;
    enable_switch();
    for (int b = 0; b < 8; b++) begin
      int s = b / 4, d = b % 4;
      if (!HW_PERM[s][d]) continue;
      reg_wr(ral.route_cfg, ROUTE_WMASK & ~(8'h1 << b));
      send(s, dest_addr(d, 'h40), 3);
      wait_idle();
      drop++;
      reg_chk(ral.err_status, ebit(s, E_DISABLED), $sformatf("ROUTE_DISABLED src%0d->dest%0d", s+1, d+1));
      clear_errors();
      // the other source to a shared destination is unaffected
      if (d >= 2) begin
        send(1 - s, dest_addr(d, 'h41), 2);
        fwd++;
      end
      reg_wr(ral.route_cfg, ROUTE_WMASK);
      send(s, dest_addr(d, 'h40), 3);
      fwd++;
      wait_idle();
      reg_chk(ral.err_status, 0, "re-enabled");
    end
    // all routes off
    reg_wr(ral.route_cfg, 0);
    for (int d = 0; d < 4; d++)
      for (int s = 0; s < 2; s++) begin
        send(s, dest_addr(d, 'h7), 1);
        drop++;
      end
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_DISABLED) | ebit(0, E_ILLEGAL) | ebit(1, E_DISABLED) | ebit(1, E_ILLEGAL),
            "all routes off");
    reg_wr(ral.route_cfg, ROUTE_WMASK);
    check_counters(fwd, drop);
  endtask
endclass

//------------------------------------------------------------------
// Address decode: unmapped space, reprogrammed ranges, overlap
// (CFG_OVERLAP, lowest destination wins), BASE > LIMIT disables a range
//------------------------------------------------------------------
class switch_addr_map_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_addr_map_vseq)

  function new(string name = "switch_addr_map_vseq");
    super.new(name);
  endfunction

  task body();
    enable_switch();
    // unmapped
    send(0, 12'h400, 1);
    send(1, 12'h7FF, 2);
    send(1, 12'hFFF, 1);
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_UNMAPPED) | ebit(1, E_UNMAPPED), "ADDR_UNMAPPED");
    reg_chk(ral.err_hdr[1], {4'h2, 12'h7FF, 8'd2, 8'h0}, "first src2 header");
    clear_errors();

    // move all ranges to the top of the space, 0x000..0x3FF now unmapped
    for (int d = 0; d < 4; d++) begin
      reg_wr(ral.dest_base[d],  'hC00 + d * 'h100);
      reg_wr(ral.dest_limit[d], 'hC00 + d * 'h100 + 'hFF);
    end
    for (int d = 0; d < 4; d++)
      for (int s = 0; s < 2; s++)
        if (HW_PERM[s][d]) begin
          send(s, 'hC00 + d * 'h100,         2);
          send(s, 'hC00 + d * 'h100 + 'hFF,  2);
        end
    send(0, 12'h010, 1);   // old dest1 address: unmapped now
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_UNMAPPED), "old map unmapped");
    clear_errors();

    // small, uneven ranges
    // (write order chosen so that no transient overlap is created)
    reg_wr(ral.dest_base[0], 'h000); reg_wr(ral.dest_limit[0], 'h000);   // single address
    reg_wr(ral.dest_base[1], 'h001); reg_wr(ral.dest_limit[1], 'h7FF);
    reg_wr(ral.dest_base[3], 'hFFF); reg_wr(ral.dest_limit[3], 'hFFF);
    reg_wr(ral.dest_base[2], 'h800); reg_wr(ral.dest_limit[2], 'hFFE);
    send(0, 'h000, 1); send(1, 'h001, 1); send(1, 'h7FF, 1);
    send(0, 'h800, 1); send(1, 'hFFE, 1); send(0, 'hFFF, 1); send(1, 'hFFF, 1);
    wait_idle();
    reg_chk(ral.err_status, 0, "uneven ranges");

    // overlap: dest2 range moved onto dest1 -> CFG_OVERLAP, dest1 wins
    reg_wr(ral.dest_base[0], 'h000); reg_wr(ral.dest_limit[0], 'h0FF);
    reg_wr(ral.dest_base[1], 'h100); reg_wr(ral.dest_limit[1], 'h1FF);
    reg_wr(ral.dest_base[2], 'h200); reg_wr(ral.dest_limit[2], 'h2FF);
    reg_wr(ral.dest_base[3], 'h300); reg_wr(ral.dest_limit[3], 'h3FF);
    clear_errors();   // the restore sequence passes through transient overlaps
    reg_chk(ral.err_status, 0, "default map, no overlap");
    reg_wr(ral.dest_base[1], 'h0F0);
    reg_chk(ral.err_status, 32'h1 << E_OVERLAP, "CFG_OVERLAP");
    send(0, 'h0F5, 2);      // dest1 (lowest wins)
    send(1, 'h0F5, 2);      // decodes to dest1 -> ILLEGAL for src2
    send(1, 'h1F0, 2);      // dest2 still reachable above the overlap
    wait_idle();
    reg_chk(ral.err_status, (32'h1 << E_OVERLAP) | ebit(1, E_ILLEGAL), "overlap decode");
    clear_errors();

    // overlap between dest3 and dest4 (both shared)
    reg_wr(ral.dest_base[1], 'h100);
    reg_wr(ral.dest_limit[2], 'h3FF);   // dest3 0x200..0x3FF covers dest4
    send(0, 'h350, 2);                   // goes to dest3
    wait_idle();
    reg_chk(ral.err_status, 32'h1 << E_OVERLAP, "dest3/dest4 overlap");
    reg_wr(ral.dest_limit[2], 'h2FF);
    clear_errors();

    // BASE > LIMIT disables the range: no overlap reported for it
    reg_wr(ral.dest_base[1], 'h1FF);
    reg_wr(ral.dest_limit[1], 'h000);
    reg_chk(ral.err_status, 0, "disabled range is not an overlap");
    send(1, 'h150, 1);                   // nothing matches -> UNMAPPED
    send(1, 'h000, 1);                   // dest1 still decodes -> ILLEGAL
    wait_idle();
    reg_chk(ral.err_status, ebit(1, E_UNMAPPED) | ebit(1, E_ILLEGAL), "disabled range");
    reg_wr(ral.dest_base[1], 'h100);
    reg_wr(ral.dest_limit[1], 'h1FF);
    clear_errors();
    send(1, 'h150, 1);
    wait_idle();
    reg_chk(ral.err_status, 0, "range restored");
  endtask
endclass

//------------------------------------------------------------------
// Packet length / framing / source ID and the check priority order
//------------------------------------------------------------------
class switch_packet_len_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_packet_len_vseq)

  function new(string name = "switch_packet_len_vseq");
    super.new(name);
  endfunction

  task body();
    enable_switch();
    // legal extremes with the default MAX_PAYLOAD = 255
    send(0, 12'h010, 1);
    send(1, 12'h110, 255);
    wait_idle();
    reg_chk(ral.err_status, 0, "size 1 and 255");

    // payload_size = 0
    send(0, 12'h010, 0, 2);
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_LEN), "size 0");
    clear_errors();

    // MAX_PAYLOAD reprogrammed
    reg_wr(ral.max_payload, 16);
    send(0, 12'h210, 16);
    send(1, 12'h310, 17);
    send(1, 12'h310, 200, 3);           // > MAX and early last: LEN once
    wait_idle();
    reg_chk(ral.err_status, ebit(1, E_LEN), "> MAX_PAYLOAD");
    reg_chk(ral.drop_cnt, {16'd2, 16'd1}, "drops so far");
    clear_errors();
    reg_wr(ral.max_payload, 1);
    send(0, 12'h010, 1);
    send(0, 12'h010, 2);
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_LEN), "MAX_PAYLOAD=1");
    reg_wr(ral.max_payload, 255);
    clear_errors();

    // early last: destination sees a short packet with last on the early beat
    send(0, 12'h020, 8, 3);
    send(1, 12'h220, 5, 0);             // last on the header
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_LEN) | ebit(1, E_LEN), "early last");
    reg_chk(ral.err_hdr[0], {4'h1, 12'h020, 8'd8, 8'h0}, "early-last header captured");
    clear_errors();

    // late last: truncated at payload_size beats, extra beats discarded
    send(0, 12'h330, 4, 9);
    send(1, 12'h130, 1, 2);
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_LEN) | ebit(1, E_LEN), "late last");
    clear_errors();
    // the next packets are framed correctly
    send(0, 12'h330, 4);
    send(1, 12'h130, 1);
    wait_idle();
    reg_chk(ral.err_status, 0, "recovery after late last");

    // src_id mismatch
    send(0, 12'h010, 2, -1, 2);
    send(1, 12'h110, 2, -1, 1);
    send(0, 12'h010, 2, -1, 0);
    send(1, 12'h110, 2, -1, 15);
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_SRCID) | ebit(1, E_SRCID), "SRCID_MISMATCH");
    clear_errors();

    // priority: only the first failing check is recorded
    send(0, 12'hF00, 0, 1, 7);          // LEN > SRCID > UNMAPPED
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_LEN), "LEN has priority");
    clear_errors();
    send(0, 12'hF00, 3, -1, 7);         // SRCID > UNMAPPED
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_SRCID), "SRCID has priority");
    clear_errors();
    send(1, 12'h050, 3, -1, 1);         // SRCID > ILLEGAL
    wait_idle();
    reg_chk(ral.err_status, ebit(1, E_SRCID), "SRCID before ILLEGAL");
    clear_errors();
    reg_wr(ral.route_cfg, 8'h00);
    send(1, 12'h050, 3);                // ILLEGAL > DISABLED
    wait_idle();
    reg_chk(ral.err_status, ebit(1, E_ILLEGAL), "ILLEGAL before DISABLED");
    reg_wr(ral.route_cfg, ROUTE_WMASK);
    clear_errors();

    // every drop/truncation outcome with the largest and smallest payload_size
    send(0, 12'h0A0, 255, 300);         // late last, src1 -> dest1
    send(0, 12'h0A1, 255, 20);          // early last
    send(1, 12'h1A0, 1, 0);             // early last (last on header), size 1
    send(0, 12'h0A2, 255, 1, 3);        // SRCID
    send(0, 12'hA00, 255, 1);           // UNMAPPED
    send(0, 12'h1A0, 255, 1);           // ILLEGAL
    reg_wr(ral.route_cfg, ROUTE_WMASK & ~8'h04);
    send(0, 12'h2A0, 255, 1);           // DISABLED
    reg_wr(ral.route_cfg, ROUTE_WMASK);
    reg_wr(ral.max_payload, 254);
    send(1, 12'h1A0, 255, 1);           // LEN, size 255 > 254
    reg_wr(ral.max_payload, 0);
    send(1, 12'h1A0, 1, 1);             // LEN, size 1 > MAX_PAYLOAD 0
    reg_wr(ral.max_payload, 255);
    wait_idle();
    reg_chk(ral.err_status, ebit(0, E_LEN) | ebit(0, E_SRCID) | ebit(0, E_UNMAPPED) | ebit(0, E_ILLEGAL) |
                            ebit(0, E_DISABLED) | ebit(1, E_LEN), "size corners");
    clear_errors();
  endtask
endclass

//------------------------------------------------------------------
// Every packet kind on both sources, under the default and under a
// reprogrammed configuration: each kind must raise exactly its own
// ERR_STATUS bit (or none for PKT_GOOD), proving the kind constraints
//------------------------------------------------------------------
class switch_pkt_kind_vseq extends switch_base_vseq;
  `uvm_object_utils(switch_pkt_kind_vseq)

  int unsigned n_per_kind = 8;

  function new(string name = "switch_pkt_kind_vseq");
    super.new(name);
  endfunction

  function bit [31:0] kind_bits(int s, pkt_kind_e k);
    case (k)
      PKT_GOOD:                                         return 0;
      PKT_SRCID_ERR:                                    return ebit(s, E_SRCID);
      PKT_UNMAPPED:                                     return ebit(s, E_UNMAPPED);
      PKT_ILLEGAL:                                      return ebit(s, E_ILLEGAL);
      PKT_DISABLED:                                     return ebit(s, E_DISABLED);
      PKT_LEN_ZERO, PKT_LEN_OVER,
      PKT_EARLY_LAST, PKT_LATE_LAST:                    return ebit(s, E_LEN);
    endcase
  endfunction

  task run_all_kinds(string tag);
    for (int s = 0; s < 2; s++) begin
      pkt_kind_e k = k.first();
      do begin
        clear_errors();
        repeat (n_per_kind) send_kind(s, k, 40, 10);
        wait_idle();
        reg_chk(ral.err_status, kind_bits(s, k), $sformatf("%s src%0d %s", tag, s+1, k.name()));
        k = k.next();
      end while (k != k.first());
    end
  endtask

  task body();
    enable_switch();
    cfg.set_ready_pct(70);
    // every kind needs: a disabled route (DISABLED) and MAX_PAYLOAD < 255 (LEN_OVER)
    reg_wr(ral.route_cfg, ROUTE_WMASK & ~8'h48);    // src1->dest4, src2->dest3 off
    reg_wr(ral.max_payload, 200);
    run_all_kinds("default map");

    // reprogrammed, uneven map with holes (every kind stays possible for both
    // sources: src2 still needs a dest1 range to build an ILLEGAL packet)
    reg_wr(ral.dest_base[3], 'hF00); reg_wr(ral.dest_limit[3], 'hF7F);
    reg_wr(ral.dest_base[2], 'h900); reg_wr(ral.dest_limit[2], 'hBFF);
    reg_wr(ral.dest_base[1], 'h400); reg_wr(ral.dest_limit[1], 'h4FF);
    reg_wr(ral.dest_base[0], 'h0F0); reg_wr(ral.dest_limit[0], 'h0FF);
    reg_wr(ral.route_cfg, ROUTE_WMASK & ~8'h84);    // src1->dest3, src2->dest4 off
    reg_wr(ral.max_payload, 33);
    clear_errors();
    for (int s = 0; s < 2; s++) begin
      pkt_kind_e k = k.first();
      do begin
        clear_errors();
        repeat (n_per_kind) send_kind(s, k, 40, 10);
        wait_idle();
        reg_chk(ral.err_status, kind_bits(s, k), $sformatf("reprogrammed src%0d %s", s+1, k.name()));
        k = k.next();
      end while (k != k.first());
    end
    cfg.set_ready_pct(100);
  endtask
endclass

`endif
