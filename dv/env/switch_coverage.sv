/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_coverage.sv
 Module/class Name             : switch_coverage
 Author                        : Vijay Bogati
 Description                   : Switch functional coverage: src x dest x outcome, payload sizes, error bits masked/unmasked, W1C and set/clear collision, arbitration order, config corners
***************************************************************/
`ifndef SWITCH_COVERAGE_SV
`define SWITCH_COVERAGE_SV

class switch_coverage extends uvm_component;
  `uvm_component_utils(switch_coverage)

  // per-packet decision (dest 4 = no range matched)
  covergroup cg_pkt with function sample(int src, int dest, switch_outcome_e oc, bit [7:0] size);
    option.per_instance = 1;
    cp_src  : coverpoint src  { bins src1 = {0}; bins src2 = {1}; }
    cp_dest : coverpoint dest { bins d[] = {[0:3]}; bins none = {4}; }
    cp_oc   : coverpoint oc;
    cp_size : coverpoint size {
      bins zero  = {0};
      bins one   = {1};
      bins short_sz = {[2:15]};
      bins mid   = {[16:254]};
      bins max   = {255};
    }
    x_src_dest_oc : cross cp_src, cp_dest, cp_oc {
      // UNMAPPED only without a matching range, and no range -> no routing outcome
      ignore_bins unm_with_dest = binsof(cp_oc) intersect {OUT_UNMAPPED} && !binsof(cp_dest.none);
      ignore_bins none_routed   = binsof(cp_dest.none) &&
                                  binsof(cp_oc) intersect {OUT_FWD, OUT_ILLEGAL, OUT_DISABLED, OUT_EARLY_LAST, OUT_LATE_LAST};
      // ILLEGAL only on the forbidden pairs, which can never be routed
      ignore_bins ill_s1   = binsof(cp_oc) intersect {OUT_ILLEGAL} && binsof(cp_src.src1) && binsof(cp_dest) intersect {0, 2, 3};
      ignore_bins ill_s2   = binsof(cp_oc) intersect {OUT_ILLEGAL} && binsof(cp_src.src2) && binsof(cp_dest) intersect {1, 2, 3};
      ignore_bins forb_s1  = binsof(cp_src.src1) && binsof(cp_dest) intersect {1} &&
                             binsof(cp_oc) intersect {OUT_FWD, OUT_DISABLED, OUT_EARLY_LAST, OUT_LATE_LAST};
      ignore_bins forb_s2  = binsof(cp_src.src2) && binsof(cp_dest) intersect {0} &&
                             binsof(cp_oc) intersect {OUT_FWD, OUT_DISABLED, OUT_EARLY_LAST, OUT_LATE_LAST};
    }
    x_oc_size : cross cp_oc, cp_size {
      ignore_bins z = binsof(cp_size.zero) && !binsof(cp_oc) intersect {OUT_LEN};
    }
  endgroup

  // ERR_STATUS bit set, with its mask state
  covergroup cg_err_set with function sample(int bit_idx, bit unmasked);
    option.per_instance = 1;
    cp_bit  : coverpoint bit_idx { bins b[] = {0, 1, 2, 3, 4, 8, 9, 10, 11, 12, 16}; }
    cp_mask : coverpoint unmasked;
    x_bit_mask : cross cp_bit, cp_mask;
  endgroup

  // ERR_STATUS bit cleared by W1C, and set/clear in the same cycle
  covergroup cg_err_clr with function sample(int bit_idx, bit set_same_cycle);
    option.per_instance = 1;
    cp_bit  : coverpoint bit_idx { bins b[] = {0, 1, 2, 3, 4, 8, 9, 10, 11, 12, 16}; }
    cp_coll : coverpoint set_same_cycle { bins normal = {0}; bins set_wins = {1}; }
  endgroup

  // packet order on shared destinations (dest3/dest4)
  covergroup cg_arb with function sample(int dest, int src, int prev_src);
    option.per_instance = 1;
    cp_dest : coverpoint dest { bins d3 = {2}; bins d4 = {3}; }
    cp_src  : coverpoint src  { bins s1 = {0}; bins s2 = {1}; }
    cp_prev : coverpoint prev_src { bins s1 = {0}; bins s2 = {1}; }
    x_order : cross cp_dest, cp_src, cp_prev;
  endgroup

  // configuration corners seen at header time
  covergroup cg_cfg with function sample(bit overlap, bit range_disabled, bit [7:0] max_payload, bit [7:0] route);
    option.per_instance = 1;
    cp_overlap  : coverpoint overlap;
    cp_disabled : coverpoint range_disabled;
    cp_maxp     : coverpoint max_payload { bins one = {1}; bins low = {[2:31]}; bins high = {[32:254]}; bins dflt = {255}; }
    cp_route    : coverpoint route { bins all_on = {8'hED}; bins all_off = {8'h00}; bins partial = default; }
  endgroup

  function new(string name = "switch_coverage", uvm_component parent = null);
    super.new(name, parent);
    cg_pkt     = new();
    cg_err_set = new();
    cg_err_clr = new();
    cg_arb     = new();
    cg_cfg     = new();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf("Coverage: pkt=%0.1f%% err_set=%0.1f%% err_clr=%0.1f%% arb=%0.1f%% cfg=%0.1f%%",
              cg_pkt.get_inst_coverage(), cg_err_set.get_inst_coverage(), cg_err_clr.get_inst_coverage(),
              cg_arb.get_inst_coverage(), cg_cfg.get_inst_coverage()), UVM_LOW)
  endfunction

endclass : switch_coverage

`endif
