/***************************************************************
 Project name                  : Switch IP
 File Name                     : stream_tx.sv
 Module/class Name             : stream_tx
 Author                        : Vijay Bogati
 Description                   : Switch packet item: header fields, payload, number of beats actually sent (for early/late last) and per-beat valid gaps
***************************************************************/
`ifndef STREAM_TX_SV
`define STREAM_TX_SV

// Packet kind: what the packet is built to exercise. Each kind fixes which
// header check (if any) the packet fails, in the spec 7.1 priority order.
typedef enum int {
  PKT_GOOD,         // forwarded: legal, enabled route, valid size, correct framing
  PKT_SRCID_ERR,    // src_id differs from the arrival port
  PKT_UNMAPPED,     // dest_id in no enabled destination range
  PKT_ILLEGAL,      // dest_id decodes to a hardware-forbidden destination
  PKT_DISABLED,     // allowed by hardware, ROUTE_CFG bit = 0
  PKT_LEN_ZERO,     // payload_size = 0
  PKT_LEN_OVER,     // payload_size > MAX_PAYLOAD
  PKT_EARLY_LAST,   // forwarded, last before payload_size beats
  PKT_LATE_LAST     // forwarded, no last after payload_size beats
} pkt_kind_e;

class stream_tx extends uvm_sequence_item;

  // header beat: {src_id[31:28], dest_id[27:16], payload_size[15:8], rsvd[7:0]}
  rand bit [3:0]    src_id;
  rand bit [11:0]   dest_id;
  rand bit [7:0]    payload_size;
  rand bit [7:0]    rsvd;

  // payload beats actually sent; last is driven on beat num_beats
  // (0 = last on the header). num_beats != payload_size gives early/late last.
  rand int unsigned num_beats;
  rand bit [31:0]   payload[];

  // idle cycles before each beat (index 0 = header)
  rand int unsigned gap[];
  int unsigned      gap_pct = 0;     // % of beats preceded by a gap

  // monitor-side view
  bit [31:0]        beats[$];        // all observed beats, header first
  time              start_time;
  time              end_time;

  constraint c_rsvd      { soft rsvd == 8'h00; }
  constraint c_beats     { soft num_beats == payload_size; num_beats <= 300; }
  constraint c_payload   { payload.size() == num_beats; }
  constraint c_gap_size  { gap.size() == num_beats + 1; }
  constraint c_gap       { foreach (gap[i]) gap[i] dist {0 := (100 - gap_pct), [1:3] := gap_pct}; }
  constraint c_order     { solve payload_size before num_beats; solve num_beats before payload; solve num_beats before gap; }

  //--------------------------------------------------------------
  // Kind mode (use_kind = 1): src_id, dest_id, payload_size and
  // num_beats are derived from 'kind' and the DUT configuration below
  // (filled from the RAL mirror by the sequence).
  //--------------------------------------------------------------
  bit               use_kind    = 0;
  rand pkt_kind_e   kind;
  rand int unsigned tgt;                      // destination index the dest_id decodes to
  int unsigned      port        = 1;          // arrival port id (1 = src1, 2 = src2)
  bit [3:0]         hw_perm     = 4'b1111;    // {d4,d3,d2,d1} hardware-allowed for this port
  bit [3:0]         route_en    = 4'b1111;    // ROUTE_CFG bits for this port
  bit [11:0]        base  [4]   = '{12'h000, 12'h100, 12'h200, 12'h300};
  bit [11:0]        limit [4]   = '{12'h0FF, 12'h1FF, 12'h2FF, 12'h3FF};
  bit [7:0]         max_payload = 8'hFF;
  int unsigned      max_size    = 255;        // cap on payload_size for forwarded kinds
  int unsigned      good_pct    = 100;        // weight of PKT_GOOD; the rest is spread over the error kinds
  bit [15:0]        kind_ok     = '1;         // kind_ok[k] = 0 removes kind k

  //--------------------------------------------------------------
  // Free mode (use_kind = 0): plain weighted fields
  //--------------------------------------------------------------
  constraint c_dest_dist { !use_kind -> dest_id dist {[12'h000:12'h3FF] :/ 85, [12'h400:12'hFFF] :/ 15}; }
  constraint c_size_dist { !use_kind -> payload_size dist {0 :/ 2, [1:16] :/ 60, [17:64] :/ 28, [65:255] :/ 10}; }

  constraint c_kind {
    use_kind -> kind_ok[kind];
    use_kind -> kind dist {PKT_GOOD := good_pct, [PKT_SRCID_ERR:PKT_LATE_LAST] :/ (100 - good_pct)};
    solve kind before tgt, src_id, dest_id, payload_size, num_beats;
    solve tgt before dest_id;
  }

  constraint c_tgt { tgt < 4; }

  // SRCID and LEN errors are found before address decode (spec 7.1), so for
  // those kinds the dest_id may also be anywhere, including no range at all
  rand bit free_dest;
  constraint c_free_dest {
    !(use_kind && kind inside {PKT_SRCID_ERR, PKT_LEN_ZERO, PKT_LEN_OVER}) -> !free_dest;
    free_dest dist {0 := 1, 1 := 1};
  }

  // src_id: correct for the port, except for a source-ID error
  constraint c_src_id {
    use_kind -> ((kind == PKT_SRCID_ERR) ? (src_id != port) : (src_id == port));
  }

  // dest_id: inside range tgt and outside every lower-numbered range
  // (lowest destination wins on overlap); outside all ranges when unmapped.
  // A range with BASE > LIMIT is empty, i.e. disabled.
  constraint c_dest_id {
    foreach (base[i]) {
      (use_kind && !free_dest && kind != PKT_UNMAPPED && tgt == i) -> dest_id inside {[base[i]:limit[i]]};
      (use_kind && !free_dest && kind != PKT_UNMAPPED && i < tgt)  -> !(dest_id inside {[base[i]:limit[i]]});
      (use_kind && kind == PKT_UNMAPPED)             -> !(dest_id inside {[base[i]:limit[i]]});
    }
  }

  // which destination the decoded range must be, per kind
  constraint c_route {
    use_kind && kind inside {PKT_GOOD, PKT_EARLY_LAST, PKT_LATE_LAST}
                                  -> (((hw_perm >> tgt) & 1) == 1) && (((route_en >> tgt) & 1) == 1);
    use_kind && kind == PKT_ILLEGAL  -> (((hw_perm >> tgt) & 1) == 0);
    use_kind && kind == PKT_DISABLED -> (((hw_perm >> tgt) & 1) == 1) && (((route_en >> tgt) & 1) == 0);
  }

  // payload_size: valid except for the two length errors
  constraint c_size {
    use_kind && kind == PKT_LEN_ZERO -> payload_size == 0;
    use_kind && kind == PKT_LEN_OVER -> payload_size > max_payload;
    use_kind && !(kind inside {PKT_LEN_ZERO, PKT_LEN_OVER})
                                    -> payload_size inside {[1:max_payload]} && payload_size <= max_size;
  }

  // framing: early / late last, short bodies for dropped packets
  constraint c_framing {
    use_kind && kind == PKT_EARLY_LAST -> num_beats < payload_size;
    use_kind && kind == PKT_LATE_LAST  -> num_beats inside {[payload_size + 1 : payload_size + 4]};
    use_kind && kind inside {PKT_LEN_ZERO, PKT_LEN_OVER} -> num_beats inside {[0:4]};
    use_kind && kind inside {PKT_GOOD, PKT_SRCID_ERR, PKT_UNMAPPED, PKT_ILLEGAL, PKT_DISABLED}
                                       -> num_beats == payload_size;
  }

  `uvm_object_utils_begin(stream_tx)
    `uvm_field_int      (src_id,       UVM_ALL_ON | UVM_HEX)
    `uvm_field_int      (dest_id,      UVM_ALL_ON | UVM_HEX)
    `uvm_field_int      (payload_size, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int      (rsvd,         UVM_ALL_ON | UVM_HEX)
    `uvm_field_int      (num_beats,    UVM_ALL_ON | UVM_DEC)
    `uvm_field_enum     (pkt_kind_e, kind, UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_field_array_int(payload,      UVM_ALL_ON | UVM_HEX)
    `uvm_field_queue_int(beats,        UVM_ALL_ON | UVM_HEX)
  `uvm_object_utils_end

  function new(string name = "stream_tx");
    super.new(name);
  endfunction

  function bit [31:0] header();
    return {src_id, dest_id, payload_size, rsvd};
  endfunction

  // beat i as driven on the bus (0 = header)
  function bit [31:0] beat(int unsigned i);
    return (i == 0) ? header() : payload[i-1];
  endfunction

  function string convert2string();
    if (beats.size() != 0)
      return $sformatf("observed pkt hdr=0x%08h beats=%0d", beats[0], beats.size());
    return $sformatf("pkt %s src_id=%0h dest_id=0x%03h size=%0d sent_beats=%0d",
                     use_kind ? kind.name() : "FREE", src_id, dest_id, payload_size, num_beats);
  endfunction

endclass : stream_tx

`endif
