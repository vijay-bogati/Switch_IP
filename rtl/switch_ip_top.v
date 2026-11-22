/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_ip_top.v
 Module/class Name             : switch_ip_top
 Author                        : Vijay Bogati
 Description                   : Top level. Connects the reset synchronizer, CSR block, two ingress blocks and the per-destination round-robin arbiters (2 sources -> 4 destinations crossbar)
***************************************************************/

//   Switch IP: 2 sources (src1, src2) -> 4 destinations (dest1..dest4),
//   address-decoded routing, fixed HW permission matrix AND software
//   ROUTE_CFG, packet-level round-robin on dest3/dest4, APB4 CSR block.
//   Hardware permission (fixed):
//     src1 -> dest1, dest3, dest4
//     src2 -> dest2, dest3, dest4
module switch_ip_top (
    input  wire        clk,
    input  wire        rst_n,

    // source 1
    input  wire        src1_valid,
    output wire        src1_ready,
    input  wire [31:0] src1_data,
    input  wire        src1_last,
    // source 2
    input  wire        src2_valid,
    output wire        src2_ready,
    input  wire [31:0] src2_data,
    input  wire        src2_last,

    // destination 1
    output wire        dest1_valid,
    input  wire        dest1_ready,
    output wire [31:0] dest1_data,
    output wire        dest1_last,
    // destination 2
    output wire        dest2_valid,
    input  wire        dest2_ready,
    output wire [31:0] dest2_data,
    output wire        dest2_last,
    // destination 3
    output wire        dest3_valid,
    input  wire        dest3_ready,
    output wire [31:0] dest3_data,
    output wire        dest3_last,
    // destination 4
    output wire        dest4_valid,
    input  wire        dest4_ready,
    output wire [31:0] dest4_data,
    output wire        dest4_last,

    // APB4 slave
    input  wire [11:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    input  wire [3:0]  pstrb,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    output wire        error
);
    localparam [3:0] HW_PERM_SRC1 = 4'b1101;  // {d4,d3,d2,d1}
    localparam [3:0] HW_PERM_SRC2 = 4'b1110;

    //-------------------------------------------------------------------------
    // Reset: asynchronous assert, synchronous de-assert
    //-------------------------------------------------------------------------
    wire rst_sync_n;
    switch_rst_sync u_rst_sync (
        .clk       (clk),
        .rst_n_in  (rst_n),
        .rst_n_out (rst_sync_n)
    );

    //-------------------------------------------------------------------------
    // CSR
    //-------------------------------------------------------------------------
    wire        switch_en;
    wire [7:0]  route_cfg;
    wire [7:0]  max_payload;
    wire [47:0] dest_base, dest_limit;

    wire [4:0]  s1_err_set,  s2_err_set;
    wire [31:0] s1_err_hdr,  s2_err_hdr;
    wire        s1_pkt_fwd,  s2_pkt_fwd;
    wire        s1_pkt_drop, s2_pkt_drop;

    switch_csr u_csr (
        .clk         (clk),
        .rst_n       (rst_sync_n),
        .paddr       (paddr),
        .psel        (psel),
        .penable     (penable),
        .pwrite      (pwrite),
        .pwdata      (pwdata),
        .pstrb       (pstrb),
        .prdata      (prdata),
        .pready      (pready),
        .pslverr     (pslverr),
        .switch_en   (switch_en),
        .route_cfg   (route_cfg),
        .max_payload (max_payload),
        .dest_base   (dest_base),
        .dest_limit  (dest_limit),
        .s1_err_set  (s1_err_set),
        .s1_err_hdr  (s1_err_hdr),
        .s1_pkt_fwd  (s1_pkt_fwd),
        .s1_pkt_drop (s1_pkt_drop),
        .s2_err_set  (s2_err_set),
        .s2_err_hdr  (s2_err_hdr),
        .s2_pkt_fwd  (s2_pkt_fwd),
        .s2_pkt_drop (s2_pkt_drop),
        .error       (error)
    );

    //-------------------------------------------------------------------------
    // Ingress (header decode + checks + one register stage)
    //-------------------------------------------------------------------------
    wire        p1_valid, p2_valid;
    wire [31:0] p1_data,  p2_data;
    wire        p1_last,  p2_last;
    wire [3:0]  p1_dest,  p2_dest;
    wire        p1_pop,   p2_pop;

    switch_ingress #(.PORT_ID(4'h1), .HW_PERM(HW_PERM_SRC1)) u_ing1 (
        .clk         (clk),
        .rst_n       (rst_sync_n),
        .src_valid   (src1_valid),
        .src_ready   (src1_ready),
        .src_data    (src1_data),
        .src_last    (src1_last),
        .switch_en   (switch_en),
        .route_en    (route_cfg[3:0]),
        .max_payload (max_payload),
        .dest_base   (dest_base),
        .dest_limit  (dest_limit),
        .pipe_valid  (p1_valid),
        .pipe_data   (p1_data),
        .pipe_last   (p1_last),
        .pipe_dest   (p1_dest),
        .pipe_pop    (p1_pop),
        .err_set     (s1_err_set),
        .err_hdr     (s1_err_hdr),
        .pkt_fwd     (s1_pkt_fwd),
        .pkt_drop    (s1_pkt_drop)
    );

    switch_ingress #(.PORT_ID(4'h2), .HW_PERM(HW_PERM_SRC2)) u_ing2 (
        .clk         (clk),
        .rst_n       (rst_sync_n),
        .src_valid   (src2_valid),
        .src_ready   (src2_ready),
        .src_data    (src2_data),
        .src_last    (src2_last),
        .switch_en   (switch_en),
        .route_en    (route_cfg[7:4]),
        .max_payload (max_payload),
        .dest_base   (dest_base),
        .dest_limit  (dest_limit),
        .pipe_valid  (p2_valid),
        .pipe_data   (p2_data),
        .pipe_last   (p2_last),
        .pipe_dest   (p2_dest),
        .pipe_pop    (p2_pop),
        .err_set     (s2_err_set),
        .err_hdr     (s2_err_hdr),
        .pkt_fwd     (s2_pkt_fwd),
        .pkt_drop    (s2_pkt_drop)
    );

    //-------------------------------------------------------------------------
    // Crossbar: one packet-level RR arbiter per destination. dest1/dest2 only
    // ever see one requester (HW permission), so their arbiters reduce to
    // pass-through in synthesis.
    //-------------------------------------------------------------------------
    wire [3:0] d_ready = {dest4_ready, dest3_ready, dest2_ready, dest1_ready};
    wire [3:0] d_valid;
    wire [3:0] d_last;
    wire [31:0] d_data [0:3];
    wire [3:0] g1, g2;     // grant to src1 / src2 per destination

    genvar d;
    generate
        for (d = 0; d < 4; d = d + 1) begin : g_dest
            wire [1:0] req = {p2_valid & p2_dest[d] & HW_PERM_SRC2[d],
                              p1_valid & p1_dest[d] & HW_PERM_SRC1[d]};
            wire [1:0] gnt;
            wire [1:0] sel = req & gnt;

            assign d_valid[d] = |sel;
            assign d_data[d]  = sel[1] ? p2_data : p1_data;
            assign d_last[d]  = sel[1] ? p2_last : p1_last;
            assign g1[d]      = sel[0];
            assign g2[d]      = sel[1];

            switch_rr_arb u_arb (
                .clk       (clk),
                .rst_n     (rst_sync_n),
                .req       (req),
                .xfer      (d_valid[d] & d_ready[d]),
                .xfer_last (d_last[d]),
                .gnt       (gnt)
            );
        end
    endgenerate

    assign p1_pop = |(g1 & d_ready);
    assign p2_pop = |(g2 & d_ready);

    assign dest1_valid = d_valid[0]; assign dest1_data = d_data[0]; assign dest1_last = d_last[0];
    assign dest2_valid = d_valid[1]; assign dest2_data = d_data[1]; assign dest2_last = d_last[1];
    assign dest3_valid = d_valid[2]; assign dest3_data = d_data[2]; assign dest3_last = d_last[2];
    assign dest4_valid = d_valid[3]; assign dest4_data = d_data[3]; assign dest4_last = d_last[3];
endmodule
