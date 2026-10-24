SHELL := /bin/bash
.DEFAULT_GOAL := all

VCS       ?= vcs
VERDI     ?= verdi

# Select one case by leaving one TOP line uncommented. Makefile comments use '#'.
# TOP     ?= sa_top_tb_smoke
# TOP     ?= sa_top_tb_int4
# TOP     ?= sa_top_tb_int8
# TOP     ?= sa_top_tb_fp16
# TOP     ?= sa_top_tb_fp32
TOP       ?= sa_top_tb_multi
DUMP      ?= fsdb

# VCS creates symbolic links while building its shared objects. VMware hgfs
# does not support those links, so all generated products live on local Linux
# storage even when this Makefile and the sources are opened from /mnt/hgfs.
RUN_ROOT  ?= $(HOME)/sa_runs/sa

RTL_FILELIST := rtl/filelist.f
TB_FILE      := tb/$(TOP).sv
TB_COMMON    := tb/sa_top_case_runner.sv

BUILD_ROOT := $(RUN_ROOT)/build/vcs
BUILD_DIR  := $(BUILD_ROOT)/$(TOP)
LOG_DIR    := $(RUN_ROOT)/logs
WAVE_DIR   := $(RUN_ROOT)/waves
SIMV       := $(BUILD_DIR)/simv
COMPILE_LOG := $(LOG_DIR)/$(TOP)_compile.log
RUN_LOG     := $(LOG_DIR)/$(TOP)_run.log
FSDB_FILE   := $(WAVE_DIR)/$(TOP).fsdb

TESTS := sa_top_tb_smoke \
         sa_top_tb_int4  \
         sa_top_tb_int8  \
         sa_top_tb_fp16  \
         sa_top_tb_fp32  \
         sa_top_tb_multi

UNIT_TESTS := output_collector_tb sa_ctrl_tb pe_array_16x16_tb

VERDI_ROOT := $(or $(VERDI_HOME),$(NOVAS_HOME))
FSDB_TAB   := $(VERDI_ROOT)/share/PLI/VCS/LINUX64/novas.tab
FSDB_LIB   := $(VERDI_ROOT)/share/PLI/VCS/LINUX64/pli.a

VCS_COMMON := -full64 -sverilog -timescale=1ns/1ps -licqueue
VCS_DEBUG  := -kdb -debug_access+all

ifeq ($(DUMP),fsdb)
  DUMP_DEFINE := +define+FSDB_TRACE
  DUMP_PLI    := -P $(FSDB_TAB) $(FSDB_LIB)
  DUMP_RUN    := +FSDB_FILE=$(FSDB_FILE)
  DUMP_CHECK  := check-fsdb
else ifeq ($(DUMP),none)
  DUMP_DEFINE :=
  DUMP_PLI    :=
  DUMP_RUN    :=
  DUMP_CHECK  :=
else
  $(error DUMP must be either fsdb or none)
endif

.PHONY: all help env dirs check-vcs check-verdi check-fsdb check-top \
        rtl compile run wave verdi regress unit-regress summary clean clean-all

# Daily entry point: compile the default test, run it, and generate its FSDB.
all: run

help:
	@echo "SA VCS/Verdi targets"
	@echo "  make all                         Compile, simulate, and generate FSDB"
	@echo "  make verdi                       Open the generated FSDB in Verdi"
	@echo "  make rtl                         Compile default 16x16 sa_top"
	@echo "  make compile TOP=sa_top_tb_int4  Compile one testbench"
	@echo "  make run TOP=sa_top_tb_int4      Compile and run one testbench"
	@echo "  make wave TOP=sa_top_tb_int4     Open its FSDB in Verdi"
	@echo "  make regress                     Run six updated SA stream tests (H=W only)"
	@echo "  make unit-regress DUMP=none       Run collector/control/array module tests"
	@echo "  make summary                     Summarize VCS run logs"
	@echo "  make run TOP=sa_top_tb_int4 DUMP=none  Run without waveform dumping"
	@echo "  make clean TOP=sa_top_tb_int4    Remove one test's generated files"
	@echo "  make clean-all                   Remove all generated files"

env:
	@echo "VCS        : $$(command -v $(VCS) 2>/dev/null || echo NOT_FOUND)"
	@echo "Verdi      : $$(command -v $(VERDI) 2>/dev/null || echo NOT_FOUND)"
	@echo "VERDI_ROOT : $(if $(VERDI_ROOT),$(VERDI_ROOT),NOT_SET)"
	@echo "Project    : $$(pwd)"
	@echo "Run root   : $(RUN_ROOT)"

dirs:
	@mkdir -p $(LOG_DIR) $(WAVE_DIR)

check-vcs:
	@command -v $(VCS) >/dev/null 2>&1 || \
	  { echo "ERROR: vcs is not in PATH. Source the Synopsys setup script first."; exit 1; }

check-verdi:
	@command -v $(VERDI) >/dev/null 2>&1 || \
	  { echo "ERROR: verdi is not in PATH. Source the Verdi setup script first."; exit 1; }

check-fsdb:
	@test -n "$(VERDI_ROOT)" || \
	  { echo "ERROR: VERDI_HOME or NOVAS_HOME is not set."; exit 1; }
	@test -f "$(FSDB_TAB)" || \
	  { echo "ERROR: FSDB PLI table not found: $(FSDB_TAB)"; exit 1; }
	@test -f "$(FSDB_LIB)" || \
	  { echo "ERROR: FSDB PLI library not found: $(FSDB_LIB)"; exit 1; }

check-top:
	@test -f "$(TB_FILE)" || \
	  { echo "ERROR: testbench does not exist: $(TB_FILE)"; exit 1; }

# Compile the synthesizable hierarchy with default parameters (16x16, 256 PEs).
rtl: check-vcs dirs
	@echo "[VCS] Compiling default 16x16 sa_top"
	@mkdir -p $(BUILD_ROOT)/sa_top_rtl
	$(VCS) $(VCS_COMMON) $(VCS_DEBUG) \
	  -f $(RTL_FILELIST) -top sa_top \
	  -Mdir=$(BUILD_ROOT)/sa_top_rtl/csrc \
	  -o $(BUILD_ROOT)/sa_top_rtl/simv \
	  -l $(LOG_DIR)/sa_top_rtl_compile.log

compile: check-vcs check-top $(DUMP_CHECK) dirs
	@echo "[VCS] Compiling $(TOP), DUMP=$(DUMP)"
	@mkdir -p $(BUILD_DIR)
	$(VCS) $(VCS_COMMON) $(VCS_DEBUG) $(DUMP_DEFINE) $(DUMP_PLI) \
	  -f $(RTL_FILELIST) $(TB_COMMON) $(TB_FILE) -top $(TOP) \
	  -Mdir=$(BUILD_DIR)/csrc \
	  -o $(SIMV) -l $(COMPILE_LOG)

run: compile
	@echo "[SIM] Running $(TOP)"
	cd "$(RUN_ROOT)" && \
	  "$(SIMV)" +vcs+lic+wait $(DUMP_RUN) -l "$(RUN_LOG)"
	@grep -q "$(TOP): PASS" "$(RUN_LOG)" || \
	  { echo "ERROR: missing $(TOP): PASS in $(RUN_LOG)"; exit 1; }
	@! grep -Eq "(^|[[:space:]])(Error|Fatal|UVM_ERROR|UVM_FATAL)(:|-|[[:space:]])" "$(RUN_LOG)" || \
	  { echo "ERROR: simulator reported an error in $(RUN_LOG)"; exit 1; }
	@echo "[SIM] Log:  $(RUN_LOG)"
	@if [ "$(DUMP)" = "fsdb" ]; then \
	  test -f "$(FSDB_FILE)" || \
	    { echo "ERROR: simulation finished but FSDB was not generated: $(FSDB_FILE)"; exit 1; }; \
	  echo "[SIM] FSDB: $(FSDB_FILE)"; \
	fi

wave verdi: check-verdi
	@test -f "$(FSDB_FILE)" || \
	  { echo "ERROR: waveform does not exist: $(FSDB_FILE). Run make run TOP=$(TOP) first."; exit 1; }
	cd "$(RUN_ROOT)" && \
	  $(VERDI) -full64 -ssf "$(FSDB_FILE)" -dbdir "$(SIMV).daidir" &

regress:
	@set -e; \
	for test in $(TESTS); do \
	  echo "============================================================"; \
	  echo "[REGRESS] $$test"; \
	  $(MAKE) --no-print-directory TOP=$$test DUMP=$(DUMP) run; \
	done
	@echo "[REGRESS] All directed tests passed."
	@$(MAKE) --no-print-directory summary

unit-regress:
	@set -e; \
	for test in $(UNIT_TESTS); do \
	  echo "[UNIT] $$test"; \
	  $(MAKE) --no-print-directory TOP=$$test DUMP=$(DUMP) run; \
	done
	@echo "[UNIT] All module tests passed."

summary: dirs
	@summary_file="$(LOG_DIR)/regression_summary.log"; \
	: > "$$summary_file"; \
	printf "%-22s %-10s %s\n" "CASE" "STATUS" "RUN_LOG" | tee -a "$$summary_file"; \
	printf "%-22s %-10s %s\n" "----------------------" "----------" "------------------------------" | tee -a "$$summary_file"; \
	for test in $(TESTS); do \
	  run_log="$(LOG_DIR)/$${test}_run.log"; \
	  if [ ! -f "$$run_log" ]; then \
	    status="NOT_RUN"; \
	  elif grep -q "$${test}: PASS" "$$run_log"; then \
	    status="PASS"; \
	  else \
	    status="FAIL"; \
	  fi; \
	  printf "%-22s %-10s %s\n" "$$test" "$$status" "$$run_log" | tee -a "$$summary_file"; \
	done; \
	echo "Summary: $$summary_file"

clean:
	@rm -rf -- "$(BUILD_DIR)"
	@rm -f -- "$(COMPILE_LOG)" "$(RUN_LOG)" "$(FSDB_FILE)"

clean-all:
	@rm -rf -- "$(BUILD_ROOT)" "$(LOG_DIR)" "$(WAVE_DIR)"
