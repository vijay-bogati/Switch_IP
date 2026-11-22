/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_if.sv
 Module/class Name             : apb_if
 Author                        : Vijay Bogati
 Description                   : APB4 interface with driver/monitor clocking blocks (single slave select)
***************************************************************/
`ifndef APB_IF_SV
`define APB_IF_SV

interface apb_if (input logic pclk, input logic presetn);
  import apb_global_pkg::*;

  logic [APB_ADDR_WIDTH-1:0] paddr;
  logic                      psel;
  logic                      penable;
  logic                      pwrite;
  logic [APB_DATA_WIDTH-1:0] pwdata;
  logic [APB_STRB_WIDTH-1:0] pstrb;
  logic [APB_DATA_WIDTH-1:0] prdata;
  logic                      pready;
  logic                      pslverr;

  // Master driver: drive 1ns after the edge, sample just before the edge
  clocking drv_cb @(posedge pclk);
    default input #1step output #1;
    output paddr, psel, penable, pwrite, pwdata, pstrb;
    input  prdata, pready, pslverr;
  endclocking

  // Passive monitor
  clocking mon_cb @(posedge pclk);
    default input #1step;
    input paddr, psel, penable, pwrite, pwdata, pstrb, prdata, pready, pslverr;
  endclocking

  modport MASTER  (clocking drv_cb, input pclk, presetn);
  modport MONITOR (clocking mon_cb, input pclk, presetn);

endinterface : apb_if

`endif
