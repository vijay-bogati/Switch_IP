/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_csr.v
 Module/class Name             : switch_csr
 Author                        : Vijay Bogati
 Description                   : APB4 slave CSR block: CTRL, ROUTE_CFG, MAX_PAYLOAD, DESTn_BASE/LIMIT, W1C ERR_STATUS, ERR_MASK, ERR_HDR capture, packet/drop counters, ID_VERSION and the error output pin
***************************************************************/

//   APB4 slave: configuration, status and counters (spec 6, 8).
//   Zero wait states (pready = 1). Unmapped offsets: pslverr = 1, read 0,
//   writes ignored. Writes to RO registers are ignored without pslverr.
module switch_csr (
    input  wire        clk,
    input  wire        rst_n,

    // APB4
    input  wire [11:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    input  wire [3:0]  pstrb,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // configuration out
    output wire        switch_en,
    output wire [7:0]  route_cfg,
    output wire [7:0]  max_payload,
    output wire [47:0] dest_base,       // {d4,d3,d2,d1}
    output wire [47:0] dest_limit,

    // events from the ingress blocks
    input  wire [4:0]  s1_err_set,
    input  wire [31:0] s1_err_hdr,
    input  wire        s1_pkt_fwd,
    input  wire        s1_pkt_drop,
    input  wire [4:0]  s2_err_set,
    input  wire [31:0] s2_err_hdr,
    input  wire        s2_pkt_fwd,
    input  wire        s2_pkt_drop,

    output wire        error
);
    //-------------------------------------------------------------------------
    // Register offsets
    //-------------------------------------------------------------------------
    localparam [11:0] A_CTRL        = 12'h000,
                      A_ROUTE_CFG   = 12'h004,
                      A_MAX_PAYLOAD = 12'h008,
                      A_D1_BASE     = 12'h010,
                      A_D1_LIMIT    = 12'h014,
                      A_D2_BASE     = 12'h018,
                      A_D2_LIMIT    = 12'h01C,
                      A_D3_BASE     = 12'h020,
                      A_D3_LIMIT    = 12'h024,
                      A_D4_BASE     = 12'h028,
                      A_D4_LIMIT    = 12'h02C,
                      A_ERR_STATUS  = 12'h030,
                      A_ERR_MASK    = 12'h034,
                      A_ERR_HDR1    = 12'h038,
                      A_ERR_HDR2    = 12'h03C,
                      A_PKT_CNT1    = 12'h040,
                      A_PKT_CNT2    = 12'h044,
                      A_DROP_CNT    = 12'h048,
                      A_ID_VERSION  = 12'h04C;

    localparam [31:0] ID_VERSION    = 32'h5357_0100;
    localparam [31:0] ERR_BITS      = 32'h0001_1F1F;  // implemented status/mask bits
    localparam [7:0]  ROUTE_WMASK   = 8'hED;          // bits 1 and 4 tied to 0

    //-------------------------------------------------------------------------
    // APB decode
    //-------------------------------------------------------------------------
    // paddr[1:0] ignored: all registers are word aligned
    wire [11:0] addr = {paddr[11:2], 2'b00};
    wire        acc  = psel & penable;
    wire        wr   = acc &  pwrite;

    reg mapped;
    always @(*) begin
        case (addr)
            A_CTRL, A_ROUTE_CFG, A_MAX_PAYLOAD,
            A_D1_BASE, A_D1_LIMIT, A_D2_BASE, A_D2_LIMIT,
            A_D3_BASE, A_D3_LIMIT, A_D4_BASE, A_D4_LIMIT,
            A_ERR_STATUS, A_ERR_MASK, A_ERR_HDR1, A_ERR_HDR2,
            A_PKT_CNT1, A_PKT_CNT2, A_DROP_CNT, A_ID_VERSION: mapped = 1'b1;
            default:                                         mapped = 1'b0;
        endcase
    end

    assign pready  = 1'b1;
    assign pslverr = acc & ~mapped;

    // byte-strobe expanded write mask
    wire [31:0] bmask = {{8{pstrb[3]}}, {8{pstrb[2]}}, {8{pstrb[1]}}, {8{pstrb[0]}}};

    // apply strobes to a register: keep un-strobed bytes, take strobed bytes
    function [31:0] wmerge;
        input [31:0] old;
        input [31:0] wd;
        input [31:0] m;
        begin
            wmerge = (old & ~m) | (wd & m);
        end
    endfunction

    //-------------------------------------------------------------------------
    // Registers
    //-------------------------------------------------------------------------
    reg        ctrl_en_q;
    reg [7:0]  route_q;
    reg [7:0]  maxp_q;
    reg [11:0] base_q  [0:3];
    reg [11:0] limit_q [0:3];
    reg [31:0] err_status_q;
    reg [31:0] err_mask_q;
    reg [31:0] err_hdr1_q, err_hdr2_q;
    reg [31:0] pkt_cnt1_q, pkt_cnt2_q;
    reg [15:0] drop1_q, drop2_q;
    reg        range_wr_q;     // a DESTn_BASE/LIMIT was written last cycle

    wire wr_range = wr & (addr >= A_D1_BASE) & (addr <= A_D4_LIMIT);

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_en_q  <= 1'b0;
            route_q    <= 8'hED;
            maxp_q     <= 8'hFF;
            for (i = 0; i < 4; i = i + 1) begin
                base_q[i]  <= i[1:0] * 12'h100;
                limit_q[i] <= i[1:0] * 12'h100 + 12'h0FF;
            end
            err_mask_q <= ERR_BITS;
            range_wr_q <= 1'b0;
        end else begin
            range_wr_q <= wr_range;
            if (wr) begin
                case (addr)
                    A_CTRL:        if (pstrb[0]) ctrl_en_q <= pwdata[0];
                    A_ROUTE_CFG:   if (pstrb[0]) route_q   <= pwdata[7:0] & ROUTE_WMASK;
                    A_MAX_PAYLOAD: if (pstrb[0]) maxp_q    <= pwdata[7:0];
                    A_ERR_MASK:    err_mask_q <= wmerge(err_mask_q, pwdata, bmask) & ERR_BITS;
                    default: ;
                endcase
                // DESTn_BASE / DESTn_LIMIT: 0x010 + 8*(n-1) (+4 for LIMIT)
                for (i = 0; i < 4; i = i + 1) begin
                    if (addr == (A_D1_BASE + i[11:0]*12'h8)) begin
                        if (pstrb[0]) base_q[i][7:0]   <= pwdata[7:0];
                        if (pstrb[1]) base_q[i][11:8]  <= pwdata[11:8];
                    end
                    if (addr == (A_D1_LIMIT + i[11:0]*12'h8)) begin
                        if (pstrb[0]) limit_q[i][7:0]  <= pwdata[7:0];
                        if (pstrb[1]) limit_q[i][11:8] <= pwdata[11:8];
                    end
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // CFG_OVERLAP: evaluated on the cycle after any DESTn_BASE/LIMIT write,
    // i.e. on the newly written values. Only enabled ranges (BASE <= LIMIT).
    //-------------------------------------------------------------------------
    reg overlap;
    integer a, b;
    always @(*) begin
        overlap = 1'b0;
        for (a = 0; a < 4; a = a + 1)
            for (b = a + 1; b < 4; b = b + 1)
                if ((base_q[a] <= limit_q[a]) && (base_q[b] <= limit_q[b]) &&
                    (base_q[a] <= limit_q[b]) && (base_q[b] <= limit_q[a]))
                    overlap = 1'b1;
    end

    //-------------------------------------------------------------------------
    // ERR_STATUS (W1C, set wins over clear) and first-error header capture
    //-------------------------------------------------------------------------
    wire [31:0] err_clr = (wr && addr == A_ERR_STATUS) ? (pwdata & bmask & ERR_BITS) : 32'b0;
    wire [31:0] err_set = {15'b0, range_wr_q & overlap,
                           3'b0, s2_err_set,
                           3'b0, s1_err_set};
    wire [31:0] err_kept = err_status_q & ~err_clr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            err_status_q <= 32'b0;
            err_hdr1_q   <= 32'b0;
            err_hdr2_q   <= 32'b0;
        end else begin
            err_status_q <= err_kept | err_set;
            if (|s1_err_set && ~|err_kept[4:0])  err_hdr1_q <= s1_err_hdr;
            if (|s2_err_set && ~|err_kept[12:8]) err_hdr2_q <= s2_err_hdr;
        end
    end

    assign error = |(err_status_q & err_mask_q);

    //-------------------------------------------------------------------------
    // Counters
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pkt_cnt1_q <= 32'b0;
            pkt_cnt2_q <= 32'b0;
            drop1_q    <= 16'b0;
            drop2_q    <= 16'b0;
        end else begin
            if (s1_pkt_fwd) pkt_cnt1_q <= pkt_cnt1_q + 32'd1;           // wraps
            if (s2_pkt_fwd) pkt_cnt2_q <= pkt_cnt2_q + 32'd1;
            if (s1_pkt_drop && drop1_q != 16'hFFFF) drop1_q <= drop1_q + 16'd1;  // saturates
            if (s2_pkt_drop && drop2_q != 16'hFFFF) drop2_q <= drop2_q + 16'd1;
        end
    end

    //-------------------------------------------------------------------------
    // Read mux
    //-------------------------------------------------------------------------
    always @(*) begin
        case (addr)
            A_CTRL:        prdata = {31'b0, ctrl_en_q};
            A_ROUTE_CFG:   prdata = {24'b0, route_q};
            A_MAX_PAYLOAD: prdata = {24'b0, maxp_q};
            A_D1_BASE:     prdata = {20'b0, base_q[0]};
            A_D1_LIMIT:    prdata = {20'b0, limit_q[0]};
            A_D2_BASE:     prdata = {20'b0, base_q[1]};
            A_D2_LIMIT:    prdata = {20'b0, limit_q[1]};
            A_D3_BASE:     prdata = {20'b0, base_q[2]};
            A_D3_LIMIT:    prdata = {20'b0, limit_q[2]};
            A_D4_BASE:     prdata = {20'b0, base_q[3]};
            A_D4_LIMIT:    prdata = {20'b0, limit_q[3]};
            A_ERR_STATUS:  prdata = err_status_q;
            A_ERR_MASK:    prdata = err_mask_q;
            A_ERR_HDR1:    prdata = err_hdr1_q;
            A_ERR_HDR2:    prdata = err_hdr2_q;
            A_PKT_CNT1:    prdata = pkt_cnt1_q;
            A_PKT_CNT2:    prdata = pkt_cnt2_q;
            A_DROP_CNT:    prdata = {drop2_q, drop1_q};
            A_ID_VERSION:  prdata = ID_VERSION;
            default:       prdata = 32'b0;
        endcase
        if (!psel) prdata = 32'b0;
    end

    //-------------------------------------------------------------------------
    // Configuration outputs
    //-------------------------------------------------------------------------
    assign switch_en   = ctrl_en_q;
    assign route_cfg   = route_q;
    assign max_payload = maxp_q;
    assign dest_base   = {base_q[3],  base_q[2],  base_q[1],  base_q[0]};
    assign dest_limit  = {limit_q[3], limit_q[2], limit_q[1], limit_q[0]};
endmodule
