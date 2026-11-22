/***************************************************************
 Project name                  : Switch IP
 File Name                     : apb_global_pkg.sv
 Module/class Name             : apb_global_pkg
 Author                        : Vijay Bogati
 Description                   : APB VIP global parameters and enums shared by the interface, agent and adapter
***************************************************************/
`ifndef APB_GLOBAL_PKG_SV
`define APB_GLOBAL_PKG_SV

package apb_global_pkg;

  // Bus widths (Switch IP: 12-bit byte address, 32-bit data)
  parameter int APB_ADDR_WIDTH = 12;
  parameter int APB_DATA_WIDTH = 32;
  parameter int APB_STRB_WIDTH = APB_DATA_WIDTH/8;

  // Maximum number of wait states the driver tolerates before flagging a hang
  parameter int APB_MAX_WAIT_STATES = 16;

  typedef enum bit {
    APB_READ  = 1'b0,
    APB_WRITE = 1'b1
  } apb_dir_e;

  typedef enum bit {
    APB_OKAY  = 1'b0,
    APB_SLVERR = 1'b1
  } apb_resp_e;

endpackage : apb_global_pkg

`endif
