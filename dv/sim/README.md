# Switch IP – running the UVM testbench

All commands run from `dv/sim` with Questa (tested: 2021.2_1, built-in UVM 1.1d).

The flow uses **one shared build**: `make build` compiles the RTL and the testbench and optimizes them once into
`build/work` (snapshot `switch_top_opt`). Every `make sim` and every test in `make regress` runs from that
same build without recompiling, so a 25-run regression compiles exactly once. Rebuild only after changing RTL or
testbench sources.

**Waveforms are off by default.** Turn them on per run with `wave=1`.

## Quick start

```sh
cd dv/sim
make build                                   # once (and after any source change)
make sim test=switch_base_test               # one test, no waves
make regress                                 # full regression from the same build
make cov                                     # merged coverage report
```

## Commands

| Command | What it does |
| --- | --- |
| `make build` | Compile RTL (`+cover=bcesf`) and testbench, optimize to `switch_top_opt` in `build/work`. Logs in `build/`. |
| `make sim test=<name>` | Run one test from the shared build into `run/<test>_<seed>/`. Fails with a message if there is no build. |
| `make regress` | Run every `<test> [seed]` line of `testlists/switch_regression.list`; writes `regression.rpt` and prints pass/fail totals. |
| `make cov` | Merge every `run/*/*.ucdb`, apply `cov_exclusions.do`, write `coverage_summary.txt` (overall + DUT-only) and `cov_html/index.html`. |
| `make view test=<name> [seed=<n>]` | Open the waveform of a run that was made with `wave=1`. |
| `make clean_runs` | Delete run results and coverage output, keep the shared build. |
| `make clean` | Delete everything, including the shared build. |

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `test=` | `switch_base_test` | UVM test name (`+UVM_TESTNAME`) |
| `seed=` | `1` | Random seed (`-sv_seed`); also part of the run folder name |
| `verbosity=` | `UVM_MEDIUM` | `+UVM_VERBOSITY` (`UVM_LOW`, `UVM_HIGH`, `UVM_DEBUG`, ...) |
| `wave=` | `0` | `1` = log waveforms to `run/<test>_<seed>/waves.wlf`; `0` = no signal logging, no WLF kept |
| `wave_scope=` | `/*` | What to log when `wave=1`, e.g. `/hdl_top/dut/*` for the DUT only (smaller, faster) |
| `gui=` | `0` | `1` = interactive Questa GUI with waves added (implies waves on) |
| `cov=` | `1` | `0` = no coverage collection (faster debug runs) |
| `list=` | `testlists/switch_regression.list` | Test list for `make regress` |
| `BUILD_DIR=` | `build` | Location of the shared build (e.g. one build per branch) |

## Examples

```sh
# debug a failing test with waves, more messages, no coverage
make sim test=switch_arbitration_test seed=7 wave=1 cov=0 verbosity=UVM_HIGH
make view test=switch_arbitration_test seed=7

# waves for the DUT only
make sim test=switch_reset_test wave=1 wave_scope=/hdl_top/dut/*

# interactive GUI
make sim test=switch_error_pin_test gui=1

# a new seed of the random test
make sim test=switch_random_test seed=$RANDOM

# regression with waves for every run (large disk use)
make regress wave=1

# your own short list
make regress list=testlists/my_smoke.list
```

## Outputs

| Path | Contents |
| --- | --- |
| `build/` | Shared build: `work/` library, `rtl_compile.log`, `tb_compile.log`, `opt.log` |
| `run/<test>_<seed>/sim.log` | Simulation log; ends with `TEST <name> : PASSED/FAILED (UVM_ERROR+FATAL = n)` |
| `run/<test>_<seed>/<test>_<seed>.ucdb` | Coverage database of the run (`cov=1`) |
| `run/<test>_<seed>/waves.wlf` | Waveform (only with `wave=1` or `gui=1`) |
| `regression.rpt` | One result line per regression run |
| `coverage_summary.txt`, `cov_html/` | Merged coverage (after `make cov`) |

A test passes only with zero `UVM_ERROR`/`UVM_FATAL`. Scoreboard mismatches and every SVA failure (APB, stream
handshake, DUT assertions) are reported as `UVM_ERROR`, so they fail the test.

## Tests

| Test | Area |
| --- | --- |
| `switch_base_test` | Smoke: every legal route once |
| `switch_reg_hw_reset_test` | CSR reset values (RAL) |
| `switch_reg_bit_bash_test` | CSR bit-bash (RAL) |
| `switch_csr_access_test` | Access types, tied bits, `pstrb`, RO, W1C, unmapped `pslverr` |
| `switch_routing_test` | Legal routes at range base / middle / limit |
| `switch_permission_test` | Hardware-forbidden routes |
| `switch_route_disable_test` | ROUTE_CFG disable / re-enable |
| `switch_addr_map_test` | Unmapped, reprogrammed, overlapping and disabled ranges |
| `switch_packet_len_test` | Sizes, early / late `last`, src_id, check priority |
| `switch_pkt_kind_test` | Every packet kind (`pkt_kind_e`) on both sources, two configurations |
| `switch_arbitration_test` | Round-robin and no interleaving on dest3 / dest4 |
| `switch_concurrency_test` | Independent destinations at full rate |
| `switch_backpressure_test` | Random ready and valid gaps |
| `switch_error_pin_test` | Mask, W1C, set-and-clear collision, ERR_HDR capture |
| `switch_dynamic_cfg_test` | Configuration changes mid-packet |
| `switch_switch_en_test` | CTRL.SWITCH_EN on / off |
| `switch_reset_test` | Asynchronous reset mid-packet |
| `switch_drop_cnt_sat_test` | DROP_CNT saturation (long: about 130k packets) |
| `switch_random_test` | Constrained-random configuration and traffic |

## Notes

- Visibility for waves (`+acc=npr`) is part of the shared build, so `wave=1` never needs a rebuild.
- Code coverage is collected on the RTL only (the RTL is compiled with `+cover`); the testbench is not instrumented.
- Runs started in parallel from different shells can share one build; give each a different `seed` (or test) so
  their run folders differ.
