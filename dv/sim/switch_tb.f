// Switch IP UVM testbench
+incdir+../vip/apb_vip/src
+incdir+../vip/stream_vip/src
+incdir+../ral
+incdir+../env
+incdir+../seq
+incdir+../test
+incdir+../top

// APB VIP
../vip/apb_vip/src/apb_global_pkg.sv
../vip/apb_vip/src/apb_if.sv
../vip/apb_vip/src/apb_assertions.sv
../vip/apb_vip/src/apb_master_pkg.sv

// Stream VIP
../vip/stream_vip/src/stream_if.sv
../vip/stream_vip/src/stream_pkg.sv

// RAL, env, sequences, tests
../ral/switch_ral_pkg.sv
../env/switch_ctrl_if.sv
../env/switch_env_pkg.sv
../seq/switch_vseq_pkg.sv
../test/switch_test_pkg.sv

// tops and DUT assertions
../top/switch_sva.sv
../top/hdl_top.sv
../top/hvl_top.sv
