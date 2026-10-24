# August18port restoration validation — 2026-10-24

Canonical SA is restored to the 2026-08-07 source snapshot
9b92a5308eb2c51ac270a35792394294bd551687. Twenty-two of23 tracked files match
the original Git blobs byte-for-byte. The only preserved deviation is the
previously authorized fp2fix.v combinational default / negative-zero correction.

The restored sa_top has exactly18 original external ports. vector_in_vld,
vector_in_last and sa_pipeline_empty are absent. output_collector is the exact
August state machine and512bit result_hold implementation. The October15cycle
buffer/token redesign has been withdrawn, archived and is not present in RTL.
The original cumulative-bus testbench has been restored without weakened checks.

## Actual local results

| Test | Questa result |
|---|---|
| sa_top_tb_smoke | PASS |
| sa_top_tb_int4 | PASS |
| sa_top_tb_int8 | PASS |
| sa_top_tb_fp16 | PASS |
| sa_top_tb_fp32 | PASS |
| sa_top_tb_multi | PASS |
| output_collector_tb | PASS |
| sa_ctrl_tb | PASS |
| pe_array_16x16_tb | PASS |

The top tests verify the original single-vector contract: one repeated-row
staircase input produces16 cumulative column snapshots. INT4/INT8/FP16/FP32 each
check one16column vector; Multi checks three separately completed vectors with
one B preload. Every output beat checks all16 lanes, X/Z, LAST and timeout.
The physical1x1 smoke checks7*3=21. These are the August tests, not the newer
independent-vector streaming tests or their superseded result counts.

Complete Questa compile has zero unsuppressed errors or warnings with the
established -suppress2892 compatibility flag. There are42 suppressed legacy
implicit-port-net diagnostics in the unmodified August source style. Focused
Verilator5.050 output_collector --lint-only --Wall has zero warnings/errors.
No new synthesis, full CDC/RDC, mapped area, power or400MHz timing signoff is
claimed. Source and log hashes are recorded in regression_result.json.

## Strict TOP contract conflict

The strict current TOP test remains preserved. Parent's actual diagnostic run
fails at2573.750ns: first accepted output lane0 is0, expected30. This is a real
protocol/behavior mismatch, not a passing integration result. That test sends
four independent4row vectors and expects seven streamed output beats; August
SA instead starts on LAST and produces W cumulative snapshots for one repeated
staircase vector. See contract_analysis.md for exact schedules and source facts.
No TOP test expectation is changed to hide this failure.

## Reproduce local verification

Run the PowerShell script run_questa.ps1 in this report. It compiles canonical
rtl/filelist.f and the original testbenches using Questa2021, then runs all nine
tops. It uses forward-slash library paths to avoid Questa Windows vopt-2253.

## Native VM waveform preparation

vm_capture_plan/run_august18_capture.sh runs the exact original Makefile's six
VCS FSDB tests, then invokes make run TOP=<unit> DUMP=none for the three units.
It launches native standalone nWave and displays exactly18 external SA ports
with no internal groups or invented interface signals. The source manifest
contains only23 HDL/build files, excluding simulator databases. This new plan
must generate new native images; prior19port/+15cycle images are superseded.
Parent owns the actual VM run and publication; this local report does not claim
those new native images already exist.
