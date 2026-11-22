# Switch IP Verification Specification

Nov 22, 2026 · Vijay Bogati

## Purpose and scope

This specification defines how the Switch IP RTL is verified and what has to be true before it is signed off. It lists the features to verify, gives each one a verification requirement with a checker and tests, and sets the stimulus, coverage and sign-off rules. The implementation is the Questa UVM testbench in `dv/`.

**In scope:** the `switch_ip_top` RTL (`rtl/`, Verilog): 2 sources and 4 destinations on valid/ready streams, address decode, the hardware permission matrix, ROUTE\_CFG, header checks and drops, early and late `last`, round-robin arbitration on dest3/dest4, the APB4 slave and its 19 CSRs, the `error` pin, counters, CTRL.SWITCH\_EN and reset.

**Out of scope:** gate-level and timing simulation, formal proof, power-aware simulation, and integration into an SoC. The open questions in spec section 9.4 (parameterised data width, `dest_id` format, per-source interrupts, buffering, programmable priority) are not features of this RTL.

| Reference | Location |
| --- | --- |
| Switch IP Specification (Nov 21, 2026) | `spec/Switch IP Specification.pdf` |
| Switch IP UVM Testbench (architecture, components, how to run) | [`dv/doc/switch_testbench.md`](switch_testbench.md) |
| Scenario-level test plan (47 scenarios, 19 tests) | `dv/doc/switch_test_plan.csv` |
| Run commands | `dv/sim/README.md` |

## Features to verify

The spec defines 14 features. Each verification requirement below traces back to one of them.

| ID | Feature | Spec section |
| --- | --- | --- |
| F01 | Valid/ready handshake on all 6 stream ports; header beat forwarded unchanged with the payload | 2, 3 |
| F02 | Address decode against DESTn\_BASE/LIMIT; lowest destination wins on overlap; BASE > LIMIT disables a range | 4 |
| F03 | Fixed hardware permission matrix (src1: dest1/3/4; src2: dest2/3/4) | 5 |
| F04 | Software route enable (ROUTE\_CFG) ANDed with the hardware permission | 5, 6 |
| F05 | Header checks in priority order: LEN, SRCID, UNMAPPED, ILLEGAL, DISABLED; only the first failure recorded | 7.1 |
| F06 | Drop behaviour: the dropped packet is fully consumed, nothing reaches any destination, DROP\_CNT +1 | 7.2 |
| F07 | Early / late `last`: truncated forwarding, `last` forced, LEN\_ERR | 8 |
| F08 | Packet-level round-robin on dest3/dest4; src1 priority after reset; no interleaving | 7.3 |
| F09 | Concurrency, back-pressure, 1-clock header latency, 1 beat per clock | 7.3, 7.4 |
| F10 | APB4 slave: zero wait states, `pslverr` on unmapped offsets, RO writes ignored, `pstrb` | 6 |
| F11 | CSRs: reset values, access types, tied-0 ROUTE\_CFG bits, counters (PKT\_CNT wraps, DROP\_CNT saturates), ID\_VERSION | 6 |
| F12 | Error handling: sticky W1C ERR\_STATUS, ERR\_MASK, `error` pin, ERR\_HDR first-error capture, set wins over clear, CFG\_OVERLAP | 8 |
| F13 | Configuration takes effect at the next header; CTRL.SWITCH\_EN holds sources off after the in-flight packet | 6, 7.4 |
| F14 | Reset: asynchronous assert, synchronous release; outputs quiet; in-flight packets discarded; CSRs to reset values | 9.1 |

## Verification approach

Verification is simulation-based and coverage-driven. It uses a UVM 1.1d testbench in Questa with a cycle-accurate reference model.

- **Environment:**
  - one APB master agent; the RAL model's front door goes through it via a `uvm_reg_adapter`, and an explicit predictor keeps the mirror
  - two stream source agents
  - four stream sink agents with random `ready`
  - one scoreboard with functional coverage
  - a virtual sequencer
  - all tests run from one shared compiled build
- **Checking:** every result is predicted, not just sampled. The scoreboard models the ingress logic, the CSRs and the error logic cycle by cycle. It checks every packet, every APB read and `pslverr`, and the `error` pin on every clock. SystemVerilog assertions check the protocol rules on every port.
- **Stimulus:** directed sequences for each scenario in spec 9.3, and packet kinds that build a packet failing exactly one chosen check under the live configuration. Constrained-random epochs also change the configuration while traffic runs.
- **Closure:** functional covergroups, RTL code coverage and assertion coverage, merged over the regression. Exclusions are allowed only for items that are unreachable by design, each with a written reason.
- **Failure policy:** a test passes only with zero `UVM_ERROR` and zero `UVM_FATAL`. Assertion failures and scoreboard mismatches are reported as `UVM_ERROR`.

## Verification requirements

Each requirement is checked automatically by the named checker and exercised by the listed tests. Scenario IDs (TP-xxx) refer to `dv/doc/switch_test_plan.csv`.

| Req | Feature | Requirement | Checker | Tests (scenarios) |
| --- | --- | --- | --- | --- |
| VR01 | F01 | `data`/`last` held stable and `valid` held until `ready`, on all 6 ports | `stream_if` SVA | all (TP-900) |
| VR02 | F01 | Header and payload arrive at the destination beat-for-beat, in order per source | Scoreboard packet compare | routing, backpressure (TP-020, TP-090) |
| VR03 | F02 | `dest_id` with BASE ≤ `dest_id` ≤ LIMIT routes to that destination, at base, middle and limit | Scoreboard decode | routing, addr\_map (TP-020, TP-051, TP-052) |
| VR04 | F02 | Overlapping ranges: lowest destination wins; a range with BASE > LIMIT matches nothing | Scoreboard decode | addr\_map, random (TP-053, TP-054) |
| VR05 | F03 | src1→dest2 and src2→dest1 always dropped with ILLEGAL\_ROUTE, whatever ROUTE\_CFG holds | Scoreboard + ERR\_STATUS model | permission (TP-030, TP-031) |
| VR06 | F04 | A cleared ROUTE\_CFG bit drops that route with ROUTE\_DISABLED; other routes unaffected | Scoreboard | route\_disable (TP-040 to TP-042) |
| VR07 | F05 | Each check fails alone and in combination; only the first failure is recorded | Scoreboard + ERR\_STATUS model | packet\_len, pkt\_kind (TP-061 to TP-067) |
| VR08 | F06 | A dropped packet is consumed to `last`, nothing reaches any destination, DROP\_CNT +1 | Scoreboard (unexpected packet, counters) | permission, pkt\_kind, random |
| VR09 | F07 | Early `last`: short packet delivered with `last`. Late `last`: `payload_size` beats with `last` forced, extra beats discarded. LEN\_ERR in both cases. | Scoreboard | packet\_len (TP-062, TP-063) |
| VR10 | F08 | src1 wins first after reset; strict alternation under contention; never interleaved | Scoreboard order + `SW_NO_INTERLEAVE` | arbitration, reset (TP-070 to TP-072, TP-131) |
| VR11 | F09 | Independent destinations run concurrently at 1 beat per clock; header reaches the destination 1 clock after acceptance | Throughput check in the sequence + scoreboard | concurrency (TP-080) |
| VR12 | F09 | Random back-pressure and valid gaps lose, duplicate or reorder nothing | Scoreboard + `stream_if` SVA | backpressure (TP-090) |
| VR13 | F10 | `pready` = 1; `pslverr` = 1 and read data 0 on unmapped offsets; RO writes ignored without `pslverr`; `pstrb` masks byte lanes | Scoreboard CSR model + `apb_assertions` | csr\_access (TP-013 to TP-015) |
| VR14 | F11 | Reset values; RW/RO/W1C behaviour; tied-0 bits; DROP\_CNT saturates per source | RAL sequences + scoreboard CSR model | reg\_hw\_reset, reg\_bit\_bash, csr\_access, drop\_cnt\_sat (TP-010 to TP-016, TP-140) |
| VR15 | F12 | `error` = OR(ERR\_STATUS & ERR\_MASK) on every clock; set wins over clear; first-error ERR\_HDR capture; CFG\_OVERLAP after a range write | Scoreboard error-pin and CSR model | error\_pin, addr\_map (TP-100 to TP-104, TP-017) |
| VR16 | F13 | Config changes mid-packet apply from the next header; SWITCH\_EN = 0 blocks new headers but lets the in-flight packet finish | Scoreboard (SWITCH\_EN check, decode) | dynamic\_cfg, switch\_en (TP-110, TP-111, TP-120, TP-121) |
| VR17 | F14 | During reset `valid`, `ready` and `error` are 0; in-flight packets are discarded; CSRs return to reset values | `SW_RESET_QUIET` + scoreboard reset + CSR reads | reset (TP-130) |

## Stimulus strategy

Stimulus has three layers: directed packets for exact corner cases, packet kinds for every check under any configuration, and constrained-random epochs that change the configuration under traffic.

**Directed packets** (`send()`) set every header field exactly: src\_id, dest\_id, payload\_size and the number of beats actually sent. They pin down range boundaries, size limits, check priority and early/late `last`.

**Packet kinds** (`pkt_kind_e`, `send_kind()`) build a packet that fails exactly one chosen check, solved against the live configuration read from the RAL mirror:

| Kind | Constraint |
| --- | --- |
| GOOD | correct src\_id; dest\_id in an allowed, enabled range; size 1..MAX\_PAYLOAD; `last` on time |
| SRCID\_ERR | src\_id ≠ port; dest\_id may be any address |
| UNMAPPED | dest\_id outside every enabled range |
| ILLEGAL | dest\_id decodes to a hardware-forbidden destination |
| DISABLED | dest\_id decodes to an allowed destination whose ROUTE\_CFG bit is 0 |
| LEN\_ZERO / LEN\_OVER | size 0 / size > MAX\_PAYLOAD; dest\_id may be any address |
| EARLY\_LAST / LATE\_LAST | valid header; `last` 1+ beats early / 1–4 beats late |

The decode constraint follows the RTL: dest\_id is inside the target range and outside every lower-numbered range, and an empty range (BASE > LIMIT) matches nothing. A kind that cannot be built in the current configuration is never chosen. `kind_ok` masks kinds out on purpose.

**Constrained random** (`switch_random_test`) runs epochs. Each epoch picks a random ROUTE\_CFG, MAX\_PAYLOAD and ERR\_MASK, and possibly moved, overlapping or disabled ranges. It then sends packets with 15% error kinds while CSR reads and W1C writes run in parallel. Throughout, `ready` probability is set per destination (5–100%) and up to 40% of beats have valid gaps. Payload data is unconstrained random.

## Checking strategy

Two independent checkers run in every test: a cycle-accurate scoreboard that predicts results, and assertions that check protocol rules. Either one failing fails the test.

**Scoreboard reference model.** All monitors sample just before clock edge E. The scoreboard then applies that edge in the hardware's order:

1. APB reads and responses are compared against the model state before E.
2. CFG\_OVERLAP is evaluated for a range write at E − 1.
3. Accepted source beats go through the ingress model.
4. APB writes update the configuration and the W1C mask.
5. ERR\_STATUS is updated, with set winning over clear, and the first error header is captured.
6. Destination packets ending at E are compared.
7. The `error` pin is compared with OR(ERR\_STATUS & ERR\_MASK).

Because the model is cycle-accurate, every CSR read is checked, including the volatile status registers, the error headers and the counters.

| Assertion set | Rules |
| --- | --- |
| `apb_assertions` | `penable` only with `psel`; SETUP is followed by ACCESS; control stable until completion; `pstrb` = 0 on reads; no X on control or response; no hang |
| `stream_if` (6 ports) | `valid` held until `ready`; `data`/`last` stable while stalled; no X on `valid`/`ready`, or on `data` while `valid` is high |
| `switch_sva` (bound in the DUT) | Outputs quiet during reset; at most one grant per destination; no interleaving on dest3/dest4 |

The RAL mirror is checked only for non-volatile registers (reset and bit-bash sequences). The scoreboard owns the volatile ones.

## Coverage plan

The goal is 100% on every metric below, merged over the regression with documented exclusions applied. Functional coverage is sampled from the scoreboard's decisions, so a bin counts only when the model agrees with the DUT.

| Model | Contents | Features | Goal |
| --- | --- | --- | --- |
| `cg_pkt` | src × dest (dest1–4 or no match) × outcome (8 outcomes), with impossible combinations ignored; outcome × payload\_size (0, 1, 2–15, 16–254, 255) | F02–F07 | 100% |
| `cg_err_set` | each of the 11 ERR\_STATUS bits set × masked / unmasked | F12 | 100% |
| `cg_err_clr` | each bit cleared by W1C × normal / set in the same cycle | F12 | 100% |
| `cg_arb` | dest3/dest4 × source × previous source | F08 | 100% |
| `cg_cfg` | overlap, disabled range, MAX\_PAYLOAD band, ROUTE\_CFG (all on, all off, partial) at header time | F02, F04, F05 | 100% |
| `cg_apb` | direction, response, strobe patterns, address window | F10 | 100% |
| Cover properties | APB write / read / error / back-to-back; stream stall and back-to-back; dest3/dest4 contention; source stall; error rising; asynchronous reset | F01, F08–F10, F12, F14 | all hit |
| Assertions | every assertion has at least one pass and no failures | all | 100% |
| RTL code coverage | statement, branch, condition, expression, FSM states and transitions, on `switch_ip_top` and its sub-blocks | all | 100% |

**Exclusion policy.** An item may be excluded only if it is unreachable by design, with the reason recorded in `dv/sim/cov_exclusions.do`. Each exclusion is reviewed at sign-off. Current exclusions:

- the src2 side of the dest1 output mux
- the two-request tie and second-source paths in the dest1 and dest2 arbiters (single requester)
- the `psel` = 0 / `penable` = 1 expression term (an APB protocol violation)
- the APB no-hang assertion (zero wait states)
- the bound `switch_sva` module's error-reporting branches (testbench code)
- the APB wait-state bin (zero wait states)

Toggle coverage is not yet part of the goal.

## Test plan and regression

19 tests cover 47 scenarios; the full scenario list with stimulus and expected results is `dv/doc/switch_test_plan.csv`. The regression (`dv/sim/testlists/switch_regression.list`) runs them as 25 seeded runs from one shared build.

| Test | Features | Seeds |
| --- | --- | --- |
| `switch_base_test` | F01, F03 | 1 |
| `switch_reg_hw_reset_test`, `switch_reg_bit_bash_test` | F11 | 1 |
| `switch_csr_access_test` | F10, F11, F12 | 1 |
| `switch_routing_test` | F01, F02 | 1 |
| `switch_permission_test` | F03 | 1 |
| `switch_route_disable_test` | F04 | 1 |
| `switch_addr_map_test` | F02, F12 | 1 |
| `switch_packet_len_test` | F05, F06, F07 | 1 |
| `switch_pkt_kind_test` | F02–F07 | 1, 5 |
| `switch_arbitration_test` | F08 | 1, 7 |
| `switch_concurrency_test` | F09 | 1 |
| `switch_backpressure_test` | F01, F09 | 1, 23 |
| `switch_error_pin_test` | F12 | 1 |
| `switch_dynamic_cfg_test` | F13 | 1 |
| `switch_switch_en_test` | F13 | 1 |
| `switch_reset_test` | F08, F14 | 1 |
| `switch_drop_cnt_sat_test` | F11 | 1 |
| `switch_random_test` | all | 1, 42, 1234, 98765 |

Before sign-off, the random test should also run on more seeds than the 4 fixed ones (`make sim test=switch_random_test seed=<n>`).

## Sign-off criteria

The RTL is signed off when all of the following hold on the final RTL and testbench, from a single shared build:

- [ ] Every run in `switch_regression.list` passes (zero `UVM_ERROR` / `UVM_FATAL`).
- [ ] `switch_random_test` passes on at least 50 additional random seeds.
- [ ] Every verification requirement VR01–VR17 has at least one passing test.
- [ ] DUT code coverage is 100% (statement, branch, condition, expression, FSM) after exclusions.
- [ ] All covergroup bins are hit (100%).
- [ ] Every assertion has passed at least once with no failures, and every cover property is hit.
- [ ] Every coverage exclusion has been reviewed and agreed, with its reason recorded.
- [ ] No open RTL bugs; every spec interpretation below agreed with the spec owner.
- [ ] Lint is clean (`vlog -lint`, no errors or warnings).

## Spec interpretations, assumptions and open issues

The spec leaves the points below open. The RTL and the reference model both implement the interpretation shown, so the regression cannot detect a different intent. Each needs agreement from the spec owner.

| ID | Topic | Interpretation used | Spec section |
| --- | --- | --- | --- |
| A1 | Early / late `last` counting | Truncated packets count in DROP\_CNT, not PKT\_CNT, and set LEN\_ERR | 7.2, 8 |
| A2 | PKT\_CNT timing | Increments when the `last` beat of an error-free packet is accepted | 6 |
| A3 | `pstrb` on W1C | Byte strobes also mask clears of ERR\_STATUS | 6 |
| A4 | ERR\_HDR capture | Captured when no error bit of that source remains set after this cycle's clear | 8 |
| A5 | Offset 0x00C, `paddr[1:0]` | 0x00C is unmapped (`pslverr`); the low two address bits are ignored | 6 |
| A6 | Reset release | A 2-flop synchronizer releases internal reset 2 clocks after `rst_n` rises | 9.1 |
| A7 | Source stall while waiting for arbitration | The header enters the source's register stage; `srcN_ready` goes low until the destination is granted | 7.3 |
| A8 | Last on the header beat | A packet with `last` on the header and a valid header is forwarded as a 1-beat packet with LEN\_ERR | 8 |

**Open issues:**

- PKT\_CNT wrap-around is not simulated, because it needs 2^32 packets. The wrap is plain modulo-2^32 addition; it can be reviewed in the code or proven formally.
- Toggle coverage is not collected yet.
- The open questions in spec section 9.4 (data width, `dest_id` format, per-source interrupts, buffering, programmable priority) would each change the RTL and this plan.

## Status against sign-off

The RTL is not yet signed off. The regression and every coverage goal are met (25 of 25 runs, 100% on all metrics); extra random seeds, the exclusion review and agreement on the interpretations are still open.

| Criterion | Status |
| --- | --- |
| Regression passes | Met: 25 of 25 runs passed, from one shared build |
| Extra random seeds (50) | Not started |
| VR01–VR17 each covered by a passing test | Met |
| DUT code coverage 100% | Met: statements 312/312, branches 217/217, conditions 32/32, expressions 66/66, FSM 6/6 states and 10/10 transitions |
| Covergroups 100% | Met: 190 of 190 bins |
| Assertions and cover properties | Met: 39 of 39 assertions passing with no failures; 24 of 24 covers hit |
| Exclusions reviewed | Pending review |
| RTL bugs | 1 found (dest3/dest4 data changed while stalled) and fixed in `rtl/switch_rr_arb.v`; none open |
| Spec interpretations A1–A8 agreed | Pending |
| Lint clean | Met (`vlog -lint`: 0 errors, 0 warnings) |
