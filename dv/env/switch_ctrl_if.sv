/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_ctrl_if.sv
 Module/class Name             : switch_ctrl_if
 Author                        : Vijay Bogati
 Description                   : Reset control and error pin observation interface used by tests, virtual sequences and the scoreboard
***************************************************************/
`ifndef SWITCH_CTRL_IF_SV
`define SWITCH_CTRL_IF_SV

interface switch_ctrl_if (input logic clk);

  logic rst_n;
  logic error;

  initial rst_n = 1'b0;

  // Synchronous reset pulse. The DUT releases reset 2 clocks after rst_n
  // rises (reset synchronizer); wait a few extra clocks before returning.
  task automatic apply_reset(int unsigned cycles = 5);
    rst_n = 1'b0;
    repeat (cycles) @(posedge clk);
    #1 rst_n = 1'b1;
    repeat (4) @(posedge clk);
    #1;
  endtask

  // Asynchronous assertion in the middle of a cycle
  task automatic assert_reset_async(int unsigned delay_ns = 3);
    @(posedge clk);
    #(delay_ns * 1ns) rst_n = 1'b0;
  endtask

  task automatic release_reset();
    @(posedge clk);
    #1 rst_n = 1'b1;
    repeat (4) @(posedge clk);
    #1;
  endtask

  task automatic wait_cycles(int unsigned n);
    repeat (n) @(posedge clk);
  endtask

endinterface : switch_ctrl_if

`endif
