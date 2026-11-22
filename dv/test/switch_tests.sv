/***************************************************************
 Project name                  : Switch IP
 File Name                     : switch_tests.sv
 Module/class Name             : switch_*_test
 Author                        : Vijay Bogati
 Description                   : Test library: each test selects its virtual sequence through a factory override of switch_base_vseq
***************************************************************/
`ifndef SWITCH_TESTS_SV
`define SWITCH_TESTS_SV

// Declares a test that runs VSEQ
`define SWITCH_TEST(TEST, VSEQ) \
class TEST extends switch_base_test; \
  `uvm_component_utils(TEST) \
  function new(string name = `"TEST`", uvm_component parent = null); \
    super.new(name, parent); \
  endfunction \
  virtual function void configure_test(); \
    switch_base_vseq::type_id::set_type_override(VSEQ::get_type()); \
  endfunction \
endclass

// smoke: switch_base_test itself (every legal route once)
`SWITCH_TEST(switch_reg_hw_reset_test,   switch_reg_hw_reset_vseq)
`SWITCH_TEST(switch_reg_bit_bash_test,   switch_reg_bit_bash_vseq)
`SWITCH_TEST(switch_csr_access_test,     switch_csr_access_vseq)
`SWITCH_TEST(switch_routing_test,        switch_routing_vseq)
`SWITCH_TEST(switch_permission_test,     switch_permission_vseq)
`SWITCH_TEST(switch_route_disable_test,  switch_route_disable_vseq)
`SWITCH_TEST(switch_addr_map_test,       switch_addr_map_vseq)
`SWITCH_TEST(switch_packet_len_test,     switch_packet_len_vseq)
`SWITCH_TEST(switch_pkt_kind_test,       switch_pkt_kind_vseq)
`SWITCH_TEST(switch_arbitration_test,    switch_arbitration_vseq)
`SWITCH_TEST(switch_concurrency_test,    switch_concurrency_vseq)
`SWITCH_TEST(switch_backpressure_test,   switch_backpressure_vseq)
`SWITCH_TEST(switch_error_pin_test,      switch_error_pin_vseq)
`SWITCH_TEST(switch_dynamic_cfg_test,    switch_dynamic_cfg_vseq)
`SWITCH_TEST(switch_switch_en_test,      switch_switch_en_vseq)
`SWITCH_TEST(switch_reset_test,          switch_reset_vseq)
`SWITCH_TEST(switch_drop_cnt_sat_test,   switch_drop_cnt_sat_vseq)
`SWITCH_TEST(switch_random_test,         switch_random_vseq)

`endif
