#***************************************************************
# Project name                  : Switch IP
# File Name                     : cov_exclusions.do
# Module/class Name             : -
# Author                        : Vijay Bogati
# Description                   : Coverage exclusions for items that are unreachable by design (each with its reason); applied to the merged UCDB by "make cov"
#***************************************************************

# dest1 can only be reached by src1 (fixed HW permission): the src2 side of
# the dest1 data/last mux (sel[1] = 1) can never be selected.
coverage exclude -scope /hdl_top/dut/g_dest[0] -linerange 193-194 -code b
coverage exclude -scope /hdl_top/dut/g_dest[0] -linerange 193-194 -code e

# psel = 0 with penable = 1 is an APB protocol violation (checked by
# APB_M_PENABLE_PSEL), so the psel_0 term of (psel & penable) is unreachable.
coverage exclude -scope /hdl_top/dut/u_csr -linerange 78 -code e

# The Switch IP APB slave has zero wait states (pready tied to 1): the
# no-hang property never has an attempt.
coverage exclude -assertpath /hdl_top/u_apb_chk/APB_S_NO_HANG

# switch_sva is testbench code bound inside the DUT: its only branches are the
# uvm_error reporting paths, which are hit only when an assertion fails.
coverage exclude -scope /hdl_top/dut/u_switch_sva -code bcesf

# dest1 / dest2 arbiters have a single possible requester (HW permission):
# the two-request tie (req == 2'b11) and the other source as owner can never
# occur. The same lines are fully covered in the dest3 / dest4 arbiters.
coverage exclude -scope /hdl_top/dut/g_dest[0]/u_arb -linerange 31-33 -code bcs
coverage exclude -scope /hdl_top/dut/g_dest[1]/u_arb -linerange 31-33 -code bcs
