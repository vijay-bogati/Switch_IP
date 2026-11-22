/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_ingress.v
 Module/class Name             : switch_ingress
 Author                        : Vijay Bogati
 Description                   : Per-source header decode, header checks (LEN, SRCID, UNMAPPED, ILLEGAL, DISABLED), packet framing (early/late last), drop handling and one register stage toward the crossbar
***************************************************************/

//   Per-source header decode, header checks, packet framing and a single
//   register stage toward the crossbar (spec 7.1, 7.2, 7.4, 8).
//   States
//     IDLE : waiting for a header beat. Ready only when CTRL.SWITCH_EN = 1.
//     FWD  : forwarding payload beats of an accepted packet.
//     DROP : consuming (discarding) beats until src_last.
//   The register stage (pipe_*) holds one beat plus its one-hot destination.
//   Header accepted at cycle T -> pipe_valid at T+1 -> destN_valid at T+1
//   when granted (1-clock header latency, 1 beat/clock throughput).
//   All configuration (ranges, ROUTE_CFG, MAX_PAYLOAD) is sampled only on the
//   header beat, so changes never affect a packet in flight.
module switch_ingress #(
    parameter [3:0] PORT_ID = 4'h1,      // expected src_id for this port
    parameter [3:0] HW_PERM = 4'b1101    // {dest4,dest3,dest2,dest1} allowed
) (
    input  wire        clk,
    input  wire        rst_n,

    // source stream
    input  wire        src_valid,
    output wire        src_ready,
    input  wire [31:0] src_data,
    input  wire        src_last,

    // configuration
    input  wire        switch_en,
    input  wire [3:0]  route_en,        // ROUTE_CFG bits for this source {d4,d3,d2,d1}
    input  wire [7:0]  max_payload,
    input  wire [47:0] dest_base,       // {d4,d3,d2,d1} x 12 bits
    input  wire [47:0] dest_limit,

    // toward crossbar
    output reg         pipe_valid,
    output reg  [31:0] pipe_data,
    output reg         pipe_last,
    output reg  [3:0]  pipe_dest,       // one-hot destination
    input  wire        pipe_pop,        // beat transferred to its destination

    // status events (single-cycle pulses)
    // (combinational, valid in the cycle the beat is accepted, so the CSR
    //  status flop is set one clock after the header beat - spec 8 step 4)
    output wire [4:0]  err_set,         // {LEN,SRCID,UNMAPPED,DISABLED,ILLEGAL}
    output wire [31:0] err_hdr,         // header of the errored packet
    output wire        pkt_fwd,         // packet forwarded without error
    output wire        pkt_drop         // packet dropped / truncated
);
    // ERR_STATUS bit positions (per source)
    localparam E_ILLEGAL  = 0;
    localparam E_DISABLED = 1;
    localparam E_UNMAPPED = 2;
    localparam E_SRCID    = 3;
    localparam E_LEN      = 4;

    localparam [1:0] S_IDLE = 2'd0,
                     S_FWD  = 2'd1,
                     S_DROP = 2'd2;

    reg [1:0]  state_q;
    reg [7:0]  remain_q;     // payload beats still expected (FWD)
    reg [3:0]  dest_q;       // one-hot destination of the current packet
    reg [31:0] hdr_q;        // header of the current packet

    //-------------------------------------------------------------------------
    // Header decode (combinational, on src_data)
    //-------------------------------------------------------------------------
    wire [3:0]  h_src_id = src_data[31:28];
    wire [11:0] h_dest   = src_data[27:16];
    wire [7:0]  h_size   = src_data[15:8];

    // range match; BASE > LIMIT never matches (range disabled)
    wire [3:0] match;
    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : g_match
            assign match[g] = (dest_base[g*12 +: 12]  <= h_dest) &&
                              (h_dest <= dest_limit[g*12 +: 12]);
        end
    endgenerate

    // lowest-numbered destination wins on overlap
    reg [3:0] dec_onehot;
    always @(*) begin
        casez (match)
            4'b???1: dec_onehot = 4'b0001;
            4'b??10: dec_onehot = 4'b0010;
            4'b?100: dec_onehot = 4'b0100;
            4'b1000: dec_onehot = 4'b1000;
            default: dec_onehot = 4'b0000;
        endcase
    end

    wire chk_len      = (h_size == 8'd0) || (h_size > max_payload);
    wire chk_srcid    = (h_src_id != PORT_ID);
    wire chk_unmapped = (dec_onehot == 4'b0000);
    wire chk_illegal  = ~|(dec_onehot & HW_PERM);
    wire chk_disabled = ~|(dec_onehot & HW_PERM & route_en);

    // first failing check only (priority order of spec 7.1)
    reg [4:0] hdr_err;
    always @(*) begin
        hdr_err = 5'b0;
        if      (chk_len)      hdr_err[E_LEN]      = 1'b1;
        else if (chk_srcid)    hdr_err[E_SRCID]    = 1'b1;
        else if (chk_unmapped) hdr_err[E_UNMAPPED] = 1'b1;
        else if (chk_illegal)  hdr_err[E_ILLEGAL]  = 1'b1;
        else if (chk_disabled) hdr_err[E_DISABLED] = 1'b1;
    end
    wire hdr_ok = (hdr_err == 5'b0);

    //-------------------------------------------------------------------------
    // Handshake
    //-------------------------------------------------------------------------
    wire pipe_free = ~pipe_valid | pipe_pop;

    assign src_ready = (state_q == S_IDLE) ? (switch_en & pipe_free) :
                       (state_q == S_FWD)  ? pipe_free :
                       /* S_DROP */          1'b1;

    wire acc = src_valid & src_ready;

    //-------------------------------------------------------------------------
    // Next-state / datapath
    //-------------------------------------------------------------------------
    reg        load;          // push accepted beat into the pipe
    reg        load_last;
    reg [3:0]  load_dest;
    reg [1:0]  state_d;
    reg [7:0]  remain_d;
    reg [4:0]  err_d;
    reg [31:0] errhdr_d;
    reg        fwd_d, drop_d;

    always @(*) begin
        load      = 1'b0;
        load_last = src_last;
        load_dest = dest_q;
        state_d   = state_q;
        remain_d  = remain_q;
        err_d     = 5'b0;
        errhdr_d  = hdr_q;
        fwd_d     = 1'b0;
        drop_d    = 1'b0;

        if (acc) begin
            case (state_q)
                S_IDLE: begin
                    errhdr_d = src_data;
                    if (hdr_ok) begin
                        load      = 1'b1;
                        load_dest = dec_onehot;
                        remain_d  = h_size;
                        if (src_last) begin
                            // early last on the header itself: truncated packet
                            err_d[E_LEN] = 1'b1;
                            drop_d       = 1'b1;
                            state_d      = S_IDLE;
                        end else begin
                            state_d = S_FWD;
                        end
                    end else begin
                        err_d   = hdr_err;
                        drop_d  = 1'b1;
                        state_d = src_last ? S_IDLE : S_DROP;
                    end
                end

                S_FWD: begin
                    load     = 1'b1;
                    remain_d = remain_q - 8'd1;
                    if (remain_q == 8'd1) begin
                        load_last = 1'b1;               // force last on final beat
                        if (src_last) begin
                            fwd_d   = 1'b1;             // well-formed packet
                            state_d = S_IDLE;
                        end else begin
                            err_d[E_LEN] = 1'b1;        // late last
                            drop_d       = 1'b1;
                            state_d      = S_DROP;      // discard up to src_last
                        end
                    end else if (src_last) begin
                        err_d[E_LEN] = 1'b1;            // early last
                        drop_d       = 1'b1;
                        state_d      = S_IDLE;
                    end
                end

                default: begin // S_DROP
                    if (src_last) state_d = S_IDLE;
                end
            endcase
        end
    end

    assign err_set  = err_d;
    assign err_hdr  = errhdr_d;
    assign pkt_fwd  = fwd_d;
    assign pkt_drop = drop_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q    <= S_IDLE;
            remain_q   <= 8'd0;
            dest_q     <= 4'b0;
            hdr_q      <= 32'b0;
            pipe_valid <= 1'b0;
            pipe_data  <= 32'b0;
            pipe_last  <= 1'b0;
            pipe_dest  <= 4'b0;
        end else begin
            state_q  <= state_d;
            remain_q <= remain_d;
            if (acc && state_q == S_IDLE) begin
                hdr_q  <= src_data;
                dest_q <= dec_onehot;
            end

            if (load) begin
                pipe_valid <= 1'b1;
                pipe_data  <= src_data;
                pipe_last  <= load_last;
                pipe_dest  <= load_dest;
            end else if (pipe_pop) begin
                pipe_valid <= 1'b0;
            end
        end
    end
endmodule
