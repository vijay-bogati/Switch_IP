/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_rr_arb.v
 Module/class Name             : switch_rr_arb
 Author                        : Vijay Bogati
 Description                   : 2-requester packet-level round-robin arbiter. src1 priority after reset, destination locked until last beat, priority passes to the other source after each packet
***************************************************************/

//   2-requester packet-level round-robin arbiter (spec 7.3).
//   - After reset, requester 0 (src1) has priority.
//   - Once a requester is granted and its first beat is offered, it owns the
//     destination until its 'last' beat transfers (no interleaving, and the
//     offered beat stays stable while destN_ready is low).
//   - After every granted packet, priority passes to the other requester.
//   gnt is a function of state and req only (never of dest_ready), so the
//   destination valid never depends combinationally on its ready.
module switch_rr_arb (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] req,        // per-source request (beat pending for this dest)
    input  wire       xfer,       // dest_valid & dest_ready this cycle
    input  wire       xfer_last,  // the transferring beat is the last of the packet
    output reg  [1:0] gnt         // one-hot grant (may be held while locked)
);
    reg locked_q;   // a packet is in progress
    reg owner_q;    // owner while locked (0 = src1, 1 = src2)
    reg prio_q;     // who wins a tie when unlocked (0 = src1, 1 = src2)

    always @(*) begin
        if (locked_q)
            gnt = owner_q ? 2'b10 : 2'b01;
        else if (req == 2'b11)
            gnt = prio_q ? 2'b10 : 2'b01;
        else
            gnt = req;
    end

    wire gnt_idx = gnt[1];
    wire offer   = |(req & gnt);   // a beat is being presented on the destination

    // Lock on the first beat *offered*, not the first beat accepted: once
    // destN_valid is high the grant (and so destN_data/last) must not change
    // until destN_ready is seen (valid/ready handshake rule, spec 2).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            locked_q <= 1'b0;
            owner_q  <= 1'b0;
            prio_q   <= 1'b0;
        end else if (xfer && xfer_last) begin
            locked_q <= 1'b0;            // packet done: release, pass priority
            prio_q   <= ~gnt_idx;
        end else if (offer) begin
            locked_q <= 1'b1;            // hold the grant (stalled beat or mid-packet)
            owner_q  <= gnt_idx;
        end
    end
endmodule
