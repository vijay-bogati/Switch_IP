/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_rst_sync.v
 Module/class Name             : switch_rst_sync
 Author                        : Vijay Bogati
 Description                   : Reset synchronizer: asynchronous assert, synchronous de-assert of rst_n
***************************************************************/

//   Reset synchronizer: asynchronous assert, synchronous de-assert (spec 9.1).
module switch_rst_sync (
    input  wire clk,
    input  wire rst_n_in,
    output wire rst_n_out
);
    reg [1:0] sync_q;

    always @(posedge clk or negedge rst_n_in) begin
        if (!rst_n_in) sync_q <= 2'b00;
        else           sync_q <= {sync_q[0], 1'b1};
    end

    assign rst_n_out = sync_q[1];
endmodule
