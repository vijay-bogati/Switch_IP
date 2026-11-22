/***************************************************************
 Project name                  : Switch IP
 File Name                     : stream_seqs.sv
 Module/class Name             : stream_base_seq, stream_pkt_seq
 Author                        : Vijay Bogati
 Description                   : Stream sequences: one packet, either with field overrides (-1 = randomize) or built from a packet kind and the DUT configuration
***************************************************************/
`ifndef STREAM_SEQS_SV
`define STREAM_SEQS_SV

class stream_base_seq extends uvm_sequence #(stream_tx);
  `uvm_object_utils(stream_base_seq)
  function new(string name = "stream_base_seq");
    super.new(name);
  endfunction
endclass : stream_base_seq

class stream_pkt_seq extends stream_base_seq;
  `uvm_object_utils(stream_pkt_seq)

  // free-mode knobs: negative value = leave random
  int src_id       = -1;
  int dest_id      = -1;
  int payload_size = -1;
  int num_beats    = -1;
  int max_size     = 255;   // upper bound for random payload_size
  int unsigned gap_pct = 0;

  // kind mode: header fields follow the packet kind and the DUT configuration
  bit          use_kind = 0;
  int          kind     = -1;        // pkt_kind_e value, -1 = random by good_pct
  int unsigned good_pct = 100;
  bit [15:0]   kind_ok  = '1;
  stream_tx    cfg_tmpl;             // carries port, hw_perm, route_en, ranges, max_payload

  stream_tx tx;             // the item sent (for the caller)

  function new(string name = "stream_pkt_seq");
    super.new(name);
  endfunction

  task body();
    tx = stream_tx::type_id::create("tx");
    tx.gap_pct = gap_pct;
    if (use_kind) begin
      if (cfg_tmpl == null) `uvm_fatal(get_type_name(), "kind mode needs cfg_tmpl (port and DUT configuration)")
      tx.use_kind    = 1;
      tx.port        = cfg_tmpl.port;
      tx.hw_perm     = cfg_tmpl.hw_perm;
      tx.route_en    = cfg_tmpl.route_en;
      tx.base        = cfg_tmpl.base;
      tx.limit       = cfg_tmpl.limit;
      tx.max_payload = cfg_tmpl.max_payload;
      tx.max_size    = max_size;
      // a forced kind must not be excluded by a zero weight in the GOOD/error split
      tx.good_pct    = (kind >= 0) ? 50 : good_pct;
      tx.kind_ok     = kind_ok;
    end
    start_item(tx);
    if (use_kind) begin
      if (!tx.randomize() with { (local::kind >= 0) -> (kind == pkt_kind_e'(local::kind)); })
        `uvm_fatal(get_type_name(), $sformatf("no legal packet of kind %0d for port %0d in this configuration", kind, cfg_tmpl.port))
    end else begin
      if (!tx.randomize() with {
            (local::src_id       >= 0) -> (src_id       == local::src_id);
            (local::dest_id      >= 0) -> (dest_id      == local::dest_id);
            (local::payload_size >= 0) -> (payload_size == local::payload_size);
            (local::payload_size <  0) -> (payload_size <= local::max_size);
            (local::num_beats    >= 0) -> (num_beats    == local::num_beats);
          })
        `uvm_fatal(get_type_name(), "stream_tx randomize failed")
    end
    finish_item(tx);
  endtask
endclass : stream_pkt_seq

`endif
