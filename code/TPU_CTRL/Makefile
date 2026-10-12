SHELL := /bin/bash
.DEFAULT_GOAL := all

VCS       ?= vcs
VERDI     ?= verdi
TOP       ?= tb_tpu_ctrl
DUMP      ?= fsdb
SIM_ARGS  ?=

# 与 sa/Makefile 一样：源码放共享目录，VCS 构建产物放虚拟机本地。
# VMware hgfs 不支持 VCS 构建共享对象时需要的符号链接。
PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
RUN_ROOT  ?= $(HOME)/tpu_ctrl_runs/TPU_CTRL
BUILD_ROOT := $(RUN_ROOT)/build/vcs
BUILD_DIR := $(BUILD_ROOT)/$(TOP)
LOG_DIR := $(RUN_ROOT)/logs
WAVE_DIR := $(RUN_ROOT)/waves
RESULT_DIR := $(PROJECT_ROOT)/results
SIMV := $(BUILD_DIR)/simv
COMPILE_LOG := $(LOG_DIR)/$(TOP)_compile.log
RUN_LOG := $(LOG_DIR)/$(TOP)_run.log
FSDB_FILE := $(WAVE_DIR)/$(TOP).fsdb
VCD_FILE := $(WAVE_DIR)/$(TOP).vcd
TB_FILE := $(PROJECT_ROOT)/tb/$(TOP).sv
RTL_REL := $(shell cat "$(PROJECT_ROOT)/rtl/filelist.f")
RTL_FILES := $(addprefix $(PROJECT_ROOT)/,$(RTL_REL))

# 与之前 TPU_CRG 工程一致，避免旧 shell 变量指向失效的许可服务器。
SCL_HOME ?= /home/yian/Synopsys/scl/2024.06
LICENSE_SERVER ?= 27000@localhost.localdomain
LICENSE_FILE ?= $(SCL_HOME)/admin/license/synopsys.lic
LMUTIL ?= $(SCL_HOME)/linux64/bin/lmutil
LMGRD ?= $(SCL_HOME)/linux64/bin/lmgrd
SNPSLMD_LICENSE_FILE = $(LICENSE_SERVER)
LM_LICENSE_FILE = $(LICENSE_SERVER)
export SNPSLMD_LICENSE_FILE LM_LICENSE_FILE

VERDI_BIN := $(shell command -v $(VERDI) 2>/dev/null)
VERDI_REAL := $(shell readlink -f "$(VERDI_BIN)" 2>/dev/null)
VERDI_AUTO_ROOT := $(patsubst %/,%,$(dir $(patsubst %/,%,$(dir $(VERDI_REAL)))))
VERDI_ROOT := $(or $(strip $(VERDI_HOME)),$(strip $(NOVAS_HOME)),$(strip $(VERDI_AUTO_ROOT)))
FSDB_TAB := $(VERDI_ROOT)/share/PLI/VCS/LINUX64/novas.tab
FSDB_LIB := $(VERDI_ROOT)/share/PLI/VCS/LINUX64/pli.a
VCS_COMMON := -full64 -sverilog -timescale=1ns/1ps
VCS_DEBUG := -kdb -debug_access+all

ifeq ($(DUMP),fsdb)
  DUMP_DEFINE := +define+FSDB_TRACE
  DUMP_PLI := -P "$(FSDB_TAB)" "$(FSDB_LIB)"
  DUMP_RUN := +FSDB_FILE="$(FSDB_FILE)"
  DUMP_CHECK := check-fsdb
else ifeq ($(DUMP),vcd)
  DUMP_DEFINE := +define+VCD_TRACE
  DUMP_PLI :=
  DUMP_RUN := +VCD_FILE="$(VCD_FILE)"
  DUMP_CHECK :=
else ifeq ($(DUMP),none)
  DUMP_DEFINE :=
  DUMP_PLI :=
  DUMP_RUN :=
  DUMP_CHECK :=
else
  $(error DUMP must be fsdb, vcd, or none)
endif

.PHONY: all help env dirs check-vcs check-verdi check-fsdb check-top license \
        rtl compile run wave verdi regress summary clean clean-all

all: run

help:
	@echo "TPU_CTRL VCS/Verdi targets (same daily workflow as sa)"
	@echo "  make / make all             Compile, self-check, generate FSDB"
	@echo "  make run                    Compile and run tb_tpu_ctrl"
	@echo "  make compile                Compile only"
	@echo "  make rtl                    Compile synthesizable CTRL hierarchy"
	@echo "  make wave / make verdi      Open FSDB in Verdi from VM desktop terminal"
	@echo "  make run DUMP=none          Run without dumping"
	@echo "  make run DUMP=vcd           Generate VCD without Verdi PLI"
	@echo "  make regress / make summary Run this unit suite / show its status"
	@echo "  make env                    Show tools, license server, and paths"
	@echo "  make clean / make clean-all Remove generated guest-local files"

dirs:
	@mkdir -p "$(BUILD_DIR)" "$(LOG_DIR)" "$(WAVE_DIR)" "$(RESULT_DIR)"

check-vcs:
	@command -v $(VCS) >/dev/null || { echo "ERROR: vcs is not in PATH; source the previous Synopsys setup first"; exit 1; }

check-verdi:
	@command -v $(VERDI) >/dev/null || { echo "ERROR: verdi is not in PATH"; exit 1; }

check-fsdb:
	@test -n "$(VERDI_ROOT)" || { echo "ERROR: set VERDI_HOME/NOVAS_HOME or put verdi in PATH"; exit 1; }
	@test -f "$(FSDB_TAB)" && test -f "$(FSDB_LIB)" || { echo "ERROR: FSDB PLI missing under $(VERDI_ROOT)"; exit 1; }

check-top:
	@test "$(TOP)" = "tb_tpu_ctrl" || { echo "ERROR: this package supports TOP=tb_tpu_ctrl"; exit 1; }
	@for src in $(RTL_FILES) "$(TB_FILE)"; do test -f "$$src" || { echo "ERROR: missing $$src"; exit 1; }; done

license: dirs
	@set -o pipefail; bash "$(PROJECT_ROOT)/scripts/check_license.sh" \
	  "$(LICENSE_SERVER)" "$(LICENSE_FILE)" "$(LMUTIL)" "$(LMGRD)" \
	  "$(LOG_DIR)" "$(HOME)/tpu_ctrl_runs/.license.lock" 2>&1 | tee "$(RESULT_DIR)/license.log"

rtl: check-vcs license dirs
	@mkdir -p "$(BUILD_ROOT)/tpu_ctrl_rtl"
	@set -o pipefail; cd "$(BUILD_ROOT)/tpu_ctrl_rtl" && \
	  $(VCS) $(VCS_COMMON) $(VCS_DEBUG) $(RTL_FILES) -top tpu_ctrl \
	  -Mdir="$(BUILD_ROOT)/tpu_ctrl_rtl/csrc" -o "$(BUILD_ROOT)/tpu_ctrl_rtl/simv" \
	  2>&1 | tee "$(LOG_DIR)/tpu_ctrl_rtl_compile.log"

compile: check-vcs check-top $(DUMP_CHECK) license dirs
	@echo "[VCS] Compiling $(TOP), DUMP=$(DUMP)"
	@set -o pipefail; cd "$(BUILD_DIR)" && \
	  $(VCS) $(VCS_COMMON) $(VCS_DEBUG) $(DUMP_DEFINE) $(DUMP_PLI) \
	  $(RTL_FILES) "$(TB_FILE)" -top $(TOP) \
	  -Mdir="$(BUILD_DIR)/csrc" -o "$(SIMV)" 2>&1 | tee "$(COMPILE_LOG)"; \
	  status=$$?; cp "$(COMPILE_LOG)" "$(RESULT_DIR)/compile.log"; exit $$status

run: compile
	@echo "[SIM] Running $(TOP)"
	@set -o pipefail; cd "$(RUN_ROOT)" && \
	  "$(SIMV)" $(DUMP_RUN) $(SIM_ARGS) 2>&1 | tee "$(RUN_LOG)"; \
	  status=$$?; cp "$(RUN_LOG)" "$(RESULT_DIR)/simulate.log"; \
	  if [ $$status -ne 0 ]; then exit $$status; fi; \
	  grep -Fq 'CTRL_UNIT_PASS checks=' "$(RUN_LOG)" || { echo "ERROR: CTRL_UNIT_PASS marker missing"; exit 1; }; \
	  if grep -Eq 'Fatal:|Error:|Error-\[|UVM_FATAL|UVM_ERROR' "$(RUN_LOG)"; then echo "ERROR: simulation failed"; exit 1; fi; \
	  if [ "$(DUMP)" = "fsdb" ]; then \
	    test -s "$(FSDB_FILE)" || { echo "ERROR: FSDB missing or empty"; exit 1; }; \
	    cp "$(FSDB_FILE)" "$(RESULT_DIR)/$(TOP).fsdb"; \
	  elif [ "$(DUMP)" = "vcd" ]; then \
	    test -s "$(VCD_FILE)" || { echo "ERROR: VCD missing or empty"; exit 1; }; \
	    cp "$(VCD_FILE)" "$(RESULT_DIR)/$(TOP).vcd"; \
	  fi; \
	  echo "[DONE] $(TOP)"; echo "[SHARED RESULTS] $(RESULT_DIR)"

# 与旧工程相同，用虚拟机图形桌面的终端执行 make verdi。
wave verdi: check-verdi
	@test -n "$$DISPLAY" || { echo "ERROR: run make verdi in the VM desktop terminal"; exit 1; }
	@test -s "$(FSDB_FILE)" || { echo "ERROR: run make all first"; exit 1; }
	@test -d "$(SIMV).daidir" || { echo "ERROR: VCS debug database missing; run make all"; exit 1; }
	@cd "$(RUN_ROOT)" && $(VERDI) -full64 -ssf "$(FSDB_FILE)" -dbdir "$(SIMV).daidir" -nologo

regress: run
	@$(MAKE) --no-print-directory summary

summary:
	@if [ ! -f "$(RUN_LOG)" ]; then echo "$(TOP): NOT_RUN"; \
	elif grep -Fq 'CTRL_UNIT_PASS checks=' "$(RUN_LOG)" && ! grep -Eq 'Fatal:|Error:|Error-\[|UVM_FATAL|UVM_ERROR' "$(RUN_LOG)"; then \
	  grep -F 'CTRL_UNIT_PASS' "$(RUN_LOG)"; \
	else echo "$(TOP): FAIL"; exit 1; fi

env:
	@echo "VCS=$$(command -v $(VCS) 2>/dev/null || echo NOT_FOUND)"
	@echo "VERDI=$$(command -v $(VERDI) 2>/dev/null || echo NOT_FOUND)"
	@echo "VERDI_ROOT=$(VERDI_ROOT)"
	@echo "PROJECT_ROOT=$(PROJECT_ROOT)"
	@echo "RUN_ROOT=$(RUN_ROOT)"
	@echo "LICENSE_SERVER=$(LICENSE_SERVER) DUMP=$(DUMP) TOP=$(TOP)"

clean:
	@set -eu; test -n "$(RUN_ROOT)"; \
	  clean_root=$$(readlink -m -- "$(RUN_ROOT)"); \
	  clean_home=$$(readlink -m -- "$(HOME)"); \
	  clean_project=$$(readlink -m -- "$(PROJECT_ROOT)"); \
	  case "$$clean_root" in /|"$$clean_home"|"$$clean_project") echo "ERROR: unsafe RUN_ROOT"; exit 1;; esac; \
	  clean_target=$$(readlink -m -- "$(BUILD_DIR)"); \
	  case "$$clean_target" in "$$clean_root"/*) ;; *) echo "ERROR: build target escapes RUN_ROOT"; exit 1;; esac; \
	  for path in "$(COMPILE_LOG)" "$(RUN_LOG)" "$(FSDB_FILE)" "$(VCD_FILE)"; do \
	    target=$$(readlink -m -- "$$path"); \
	    case "$$target" in "$$clean_root"/*) ;; *) echo "ERROR: generated file escapes RUN_ROOT"; exit 1;; esac; \
	  done; \
	  rm -rf -- "$$clean_target"; \
	  rm -f -- "$(COMPILE_LOG)" "$(RUN_LOG)" "$(FSDB_FILE)" "$(VCD_FILE)"

clean-all:
	@set -eu; test -n "$(RUN_ROOT)"; \
	  clean_root=$$(readlink -m -- "$(RUN_ROOT)"); \
	  clean_home=$$(readlink -m -- "$(HOME)"); \
	  clean_project=$$(readlink -m -- "$(PROJECT_ROOT)"); \
	  case "$$clean_root" in /|"$$clean_home"|"$$clean_project") echo "ERROR: unsafe RUN_ROOT"; exit 1;; esac; \
	  for path in "$(BUILD_ROOT)" "$(LOG_DIR)" "$(WAVE_DIR)"; do \
	    target=$$(readlink -m -- "$$path"); \
	    case "$$target" in "$$clean_root"/*) ;; *) echo "ERROR: cleanup target escapes RUN_ROOT"; exit 1;; esac; \
	  done; \
	  rm -rf -- "$(BUILD_ROOT)" "$(LOG_DIR)" "$(WAVE_DIR)"
