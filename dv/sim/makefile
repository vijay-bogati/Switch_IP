#***************************************************************
# Project name                  : Switch IP
# File Name                     : makefile
# Module/class Name             : -
# Author                        : Vijay Bogati
# Description                   : Questa flow: one shared build (RTL with code coverage + UVM TB, optimized once), any number of test runs from that build, regression, coverage merge. Waveforms off by default
#***************************************************************
#
#  make build                                      compile + optimize once into the shared build
#  make sim     test=<test> [seed=<n>] [wave=1] [gui=1] [cov=0] [verbosity=UVM_HIGH]
#  make regress [list=<file>] [wave=1] [cov=0]
#  make cov                                        merge UCDBs, apply exclusions, reports
#  make view    test=<test> [seed=<n>]             open a run's waveform
#  make clean | clean_runs
#  (see README.md)
#

#----------------------------------------------------------------
# Knobs
#----------------------------------------------------------------
test       ?= switch_base_test
seed       ?= 1
verbosity  ?= UVM_MEDIUM
list       ?= testlists/switch_regression.list
wave       ?= 0              # 1 = log waveforms to run/<test>_<seed>/waves.wlf
wave_scope ?= /*             # what to log when wave=1 (e.g. /hdl_top/dut/*)
gui        ?= 0              # 1 = interactive GUI (logs waves of the scope above)
cov        ?= 1              # 1 = collect coverage (UCDB per run)

#----------------------------------------------------------------
# Shared build: compiled once, used read-only by every run
#----------------------------------------------------------------
BUILD_DIR  ?= build
LIB         = $(BUILD_DIR)/work
TOP_OPT     = switch_top_opt
RUN_DIR     = run/$(test)_$(seed)

ifeq ($(strip $(cov)),1)
  VSIM_COV  = -coverage
  COV_SAVE  = coverage save -onexit -codeAll -cvg -assert -directive $(RUN_DIR)/$(test)_$(seed).ucdb;
endif

ifeq ($(strip $(gui)),1)
  WAVE_ON   = 1
else
  WAVE_ON   = $(strip $(wave))
endif

ifeq ($(WAVE_ON),1)
  VSIM_WLF  = -wlf $(RUN_DIR)/waves.wlf
  WAVE_LOG  = log -r $(strip $(wave_scope));
else
  VSIM_WLF  = -wlf $(RUN_DIR)/waves.wlf -wlfdeleteonquit
  WAVE_LOG  =
endif

ifeq ($(strip $(gui)),1)
  VSIM_MODE = -gui -do "$(WAVE_LOG) add wave -r /hdl_top/*; $(COV_SAVE) run -all"
else
  VSIM_MODE = -c -do "$(WAVE_LOG) $(COV_SAVE) run -all; quit -f"
endif

.PHONY: usage all build compile check_build sim regress cov view clean clean_runs

usage:
	@sed -n '9,16p' makefile

all: build sim

#----------------------------------------------------------------
# Build (once)
#----------------------------------------------------------------
build:
	rm -rf $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)
	vlib $(LIB)
	vlog -work $(LIB) -l $(BUILD_DIR)/rtl_compile.log +cover=bcesf -f switch_rtl.f
	vlog -work $(LIB) -l $(BUILD_DIR)/tb_compile.log -sv -timescale 1ns/1ps -f switch_tb.f
	vopt -work $(LIB) -l $(BUILD_DIR)/opt.log +acc=npr hdl_top hvl_top -o $(TOP_OPT)
	@echo "Shared build ready: $(LIB) ($(TOP_OPT))"

compile: build

check_build:
	@test -f $(LIB)/_info || { echo "No shared build in $(LIB): run 'make build' first"; exit 1; }

#----------------------------------------------------------------
# One test run from the shared build
#----------------------------------------------------------------
sim: check_build
	mkdir -p $(RUN_DIR)
	vsim -lib $(LIB) $(TOP_OPT) $(VSIM_COV) -sv_seed $(seed) \
	     +UVM_TESTNAME=$(test) +UVM_VERBOSITY=$(verbosity) \
	     -assertdebug -l $(RUN_DIR)/sim.log $(VSIM_WLF) $(VSIM_MODE) < /dev/null
	@grep -E "TEST .* : (PASSED|FAILED)" $(RUN_DIR)/sim.log || echo "TEST $(test) : NO RESULT (see $(RUN_DIR)/sim.log)"

#----------------------------------------------------------------
# Regression: every '<test> [seed]' line of the list, same shared build
#----------------------------------------------------------------
regress: check_build
	@rm -f regression.rpt
	@grep -v -E '^\s*(#|$$)' $(list) | while read t s; do \
	   s=$${s:-1}; \
	   $(MAKE) --no-print-directory sim test=$$t seed=$$s wave=$(strip $(wave)) cov=$(strip $(cov)) \
	           verbosity=$(verbosity) < /dev/null > /dev/null 2>&1; \
	   r=$$(grep -h -E "TEST .* : (PASSED|FAILED)" run/$${t}_$${s}/sim.log 2>/dev/null | sed 's/^# *//'); \
	   echo "$${r:-TEST $$t : NO RESULT} [seed $$s]" | tee -a regression.rpt; \
	 done
	@echo "------------------------------------------------------------"
	@echo " passed: $$(grep -c PASSED regression.rpt)   failed: $$(grep -c -v PASSED regression.rpt)"
	@echo "------------------------------------------------------------"

#----------------------------------------------------------------
# Coverage merge + reports
#----------------------------------------------------------------
cov:
	vcover merge -out merged.ucdb run/*/*.ucdb
	vsim -c -viewcov merged.ucdb -do "do cov_exclusions.do; coverage save merged.ucdb; quit -f" -l cov_exclusions.log < /dev/null
	vcover report -summary merged.ucdb > coverage_summary.txt
	vcover report -instance=/hdl_top/dut -recursive -code bcesf merged.ucdb | tee -a coverage_summary.txt
	vcover report -html -details -htmldir cov_html merged.ucdb
	@echo "HTML report: cov_html/index.html"

#----------------------------------------------------------------
# Waveform viewer for a run made with wave=1
#----------------------------------------------------------------
view:
	@test -f $(RUN_DIR)/waves.wlf || { echo "No $(RUN_DIR)/waves.wlf: rerun with wave=1"; exit 1; }
	vsim -view $(RUN_DIR)/waves.wlf -do "add wave -r /*" &

#----------------------------------------------------------------
clean_runs:
	rm -rf run regression.rpt merged.ucdb cov_html coverage_summary.txt cov_exclusions.log transcript

clean: clean_runs
	rm -rf $(BUILD_DIR) work *.log *.wlf
