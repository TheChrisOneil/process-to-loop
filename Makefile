# process-to-loop. Every command a person runs is here.
SHELL := /bin/bash
OUT   ?= build

help:
	@echo "make design DESIGN=<path>                        validate a design, 25 rules"
	@echo "make compile DESIGN=<path> NAME=<formula-name>   design -> formula + check scripts"
	@echo "make conformance NAME=<formula-name>             ask the installed gc"
	@echo "make rules                                       both rule sets"
	@echo "make probe                                       what gc itself enforces"
	@echo "make demo                                        compile the worked example"
	@echo "make test                                        everything, end to end"
	@echo "make clean                                       remove $(OUT)/"

design:
	@[ -n "$(DESIGN)" ] || { echo "make design DESIGN=<path>"; exit 64; }
	@tooling/validate.sh "$(DESIGN)"

compile:
	@[ -n "$(DESIGN)" ] && [ -n "$(NAME)" ] || { echo "make compile DESIGN=<path> NAME=<formula-name>"; exit 64; }
	@tooling/compile.sh "$(DESIGN)" --name "$(NAME)" --out "$(OUT)"

conformance:
	@[ -n "$(NAME)" ] || { echo "make conformance NAME=<formula-name>"; exit 64; }
	@command -v gc >/dev/null || { echo "REFUSED: gc is not installed, so nothing can confirm this compiles."; exit 1; }
	@tooling/conformance.sh "$(OUT)" "$(NAME)"

rules:
	@echo "THE DESIGN RULES — is the method sound?"
	@tooling/validate.sh --rules | sed 's/^/  /'
	@echo
	@echo "THE FORMULA RULES — is the emitted formula defensible?"
	@sed -n 's/^ *fail("\(F[0-9]*\)", *"\(.*\)".*/  \1  \2/p' tooling/lib/validate-formula.awk

probe: ; @./probe.sh

demo:
	@$(MAKE) --no-print-directory compile DESIGN=examples/invoices.design NAME=invoice-reconciliation
	@$(MAKE) --no-print-directory conformance NAME=invoice-reconciliation

test: ; @./test.sh

clean: ; @rm -rf $(OUT) && echo "cleaned $(OUT)/"

.PHONY: help design compile conformance rules probe demo test clean
