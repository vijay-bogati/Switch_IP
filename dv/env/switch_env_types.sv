/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_env_types.sv
 Module/class Name             : switch_outcome_e, switch_exp_pkt
 Author                        : Vijay Bogati
 Description                   : Environment-wide constants, packet outcome enum and the expected-packet container used by the scoreboard
***************************************************************/
`ifndef SWITCH_ENV_TYPES_SV
`define SWITCH_ENV_TYPES_SV

// CSR offsets
localparam bit [11:0] CSR_CTRL        = 12'h000;
localparam bit [11:0] CSR_ROUTE_CFG   = 12'h004;
localparam bit [11:0] CSR_MAX_PAYLOAD = 12'h008;
localparam bit [11:0] CSR_DEST1_BASE  = 12'h010;   // + 8*n, LIMIT at +4
localparam bit [11:0] CSR_DEST4_LIMIT = 12'h02C;
localparam bit [11:0] CSR_ERR_STATUS  = 12'h030;
localparam bit [11:0] CSR_ERR_MASK    = 12'h034;
localparam bit [11:0] CSR_ERR_HDR1    = 12'h038;
localparam bit [11:0] CSR_ERR_HDR2    = 12'h03C;
localparam bit [11:0] CSR_PKT_CNT1    = 12'h040;
localparam bit [11:0] CSR_PKT_CNT2    = 12'h044;
localparam bit [11:0] CSR_DROP_CNT    = 12'h048;
localparam bit [11:0] CSR_ID_VERSION  = 12'h04C;

localparam bit [31:0] ID_VERSION_VAL  = 32'h5357_0100;
localparam bit [31:0] ERR_BITS        = 32'h0001_1F1F;
localparam bit [7:0]  ROUTE_WMASK     = 8'hED;

// per-source ERR_STATUS bit positions (src2 = +8)
localparam int E_ILLEGAL  = 0;
localparam int E_DISABLED = 1;
localparam int E_UNMAPPED = 2;
localparam int E_SRCID    = 3;
localparam int E_LEN      = 4;
localparam int E_OVERLAP  = 16;

// fixed hardware permission {d4,d3,d2,d1}
localparam bit [3:0] HW_PERM [2] = '{4'b1101, 4'b1110};

typedef enum int {
  OUT_FWD,          // forwarded, well formed
  OUT_LEN,          // payload_size 0 or > MAX_PAYLOAD (header)
  OUT_SRCID,
  OUT_UNMAPPED,
  OUT_ILLEGAL,
  OUT_DISABLED,
  OUT_EARLY_LAST,   // truncated: last before payload_size beats
  OUT_LATE_LAST     // truncated: no last after payload_size beats
} switch_outcome_e;

typedef enum int { ING_IDLE, ING_FWD, ING_DROP } ing_state_e;

// Expected packet at one destination
class switch_exp_pkt;
  int        src;
  int        dest;
  bit [31:0] beats[$];
  bit        complete;
endclass

`endif
