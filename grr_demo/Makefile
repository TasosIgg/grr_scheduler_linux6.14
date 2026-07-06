# ==============================
# GRR Scheduler Demo Makefile
# ==============================

CC      := gcc
CFLAGS  := -O2 -Wall -Wextra
TARGETS := assign_ncores assign_process grr_worker
SCRIPT  := demo_grr_answers.sh

# Default target
all: $(TARGETS)

# ------------------------------
# Build rules
# ------------------------------

assign_ncores: assign_ncores.c
	$(CC) $(CFLAGS) $< -o $@

assign_process: assign_process.c
	$(CC) $(CFLAGS) $< -o $@

grr_worker: grr_worker.c
	$(CC) $(CFLAGS) $< -o $@

# ------------------------------
# Demo targets
# ------------------------------

.PHONY: run demo clean info make_script_executable

info:
	@echo "CPUs detected: $$(nproc)"

make_script_executable:
	@if [ ! -x "$(SCRIPT)" ]; then \
		echo "Making $(SCRIPT) executable"; \
		chmod +x $(SCRIPT); \
	fi

demo: all make_script_executable
	@echo "Run with: sudo make run"

run: demo
	@echo "======================================"
	@echo " Running GRR Scheduler Demonstration "
	@echo "======================================"
	sudo ./$(SCRIPT)

# ------------------------------
# Cleanup
# ------------------------------

clean:
	rm -f $(TARGETS)
