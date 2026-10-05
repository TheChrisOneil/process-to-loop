# process-to-loop. Every command a person runs is here.
SHELL := /bin/bash
OUT   ?= build
BUNDLES ?= bundles

help:
	@echo "make design DESIGN=<path>                        validate a design, 25 rules"
	@echo "make compile DESIGN=<path> NAME=<formula-name>   design -> formula + check scripts"
	@echo "make conformance NAME=<formula-name>             ask the installed gc"
	@echo "make bundle DESIGN=<path> NAME=<bundle-name>     design -> a standalone RPA bundle + launchd job"
	@echo "make properties DESIGN=<path> STEP=<id>          what one step's type promises"
	@echo "make diagram DESIGN=<path>                       a sequence diagram, by rule not by model"
	@echo "make flow DESIGN=<path>                          a flowchart, coloured by step type"
	@echo "make brief DESIGN=<path>                         BRIEF.md and diagrams/ beside the design"
	@echo "make city-preflight CITY=<dir>                   is this city safe to build formulas against?"
	@echo "make pack-diff A=<pack-dir> B=<pack-dir>         what actually changed between two pack versions"
	@echo "make formula-preflight F=<formula> RIG=<dir> V='k=v ...'   does everything it names resolve?"
	@echo "make run-report T=<transcript.jsonl>              where a run spent its time and tokens"
	@echo "make rules                                       both rule sets"
	@echo "make probe                                       what gc itself enforces"
	@echo "make demo                                        compile the worked example"
	@echo "make install-mayor CITY=<dir>                    put the front-door prompt in a city"
	@echo "make install-city CITY=<dir>                     sync formulas into a city"
	@echo "make install-rig RIG=<dir>                       sync checks and tooling into a rig (checks resolve HERE)"
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

bundle:
	@[ -n "$(DESIGN)" ] && [ -n "$(NAME)" ] || { echo "make bundle DESIGN=<path> NAME=<bundle-name> [CHECKS=<dir>] [INTERVAL=<sec>]"; exit 64; }
	@tooling/emit-bundle.sh "$(DESIGN)" --name "$(NAME)" --out "$(BUNDLES)" \
	   $(if $(CHECKS),--checks "$(CHECKS)",) $(if $(INTERVAL),--interval "$(INTERVAL)",)

city-preflight:
	@tooling/city-preflight.sh $(if $(CITY),--city "$(CITY)",) $(if $(OFFLINE),--offline,)

diagram:
	@[ -n "$(DESIGN)" ] || { echo "make diagram DESIGN=<path>"; exit 64; }
	@tooling/render.sh "$(DESIGN)"

flow:
	@[ -n "$(DESIGN)" ] || { echo "make flow DESIGN=<path>"; exit 64; }
	@tooling/render.sh --flow "$(DESIGN)"

brief:
	@[ -n "$(DESIGN)" ] || { echo "make brief DESIGN=<path>"; exit 64; }
	@tooling/brief.sh "$(DESIGN)"

pack-capability:
	@[ -n "$(PACK)" ] || { echo "make pack-capability PACK=<pack-dir>"; exit 64; }
	@tooling/pack-capability.sh "$(PACK)"

pack-diff:
	@[ -n "$(A)" ] && [ -n "$(B)" ] || { echo "make pack-diff A=<pack-dir> B=<pack-dir>"; exit 64; }
	@tooling/pack-diff.sh "$(A)" "$(B)"

properties:
	@[ -n "$(DESIGN)" ] && [ -n "$(STEP)" ] || { echo "make properties DESIGN=<path> STEP=<id>"; exit 64; }
	@tooling/properties.sh "$(DESIGN)" "$(STEP)"

formula-preflight:
	@[ -n "$(F)" ] && [ -n "$(RIG)" ] || { echo "make formula-preflight F=<formula.toml> RIG=<rig-dir> V='k=v ...'"; exit 64; }
	@tooling/formula-preflight.sh "$(F)" "$(RIG)" $(V)

run-report:
	@[ -n "$(T)" ] || { echo "make run-report T=<transcript.jsonl>   (or T=--latest D=<dir>)"; exit 64; }
	@tooling/run-report.sh "$(T)" $(D)

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

install-rig:
	@[ -n "$(RIG)" ] || { echo "make install-rig RIG=<rig-dir>"; exit 64; }
	@[ -d "$(RIG)" ] || { echo "no such rig directory: $(RIG)"; exit 65; }
	@for d in checks tooling lib; do \
	   [ -d "$$d" ] || continue; \
	   mkdir -p "$(RIG)/$$d"; \
	   cp -pR "$$d"/. "$(RIG)/$$d/"; \
	   echo "  synced $$d/ -> $(RIG)/$$d/"; \
	 done
	@echo "A formula's check paths are relative to the RIG working directory,"
	@echo "not the city. Checks installed only in the city are never found."

install-city:
	@[ -n "$(CITY)" ] || { echo "make install-city CITY=<city-dir>"; exit 64; }
	@[ -f "$(CITY)/city.toml" ] || { echo "not a city: $(CITY)/city.toml is not there"; exit 65; }
	@for d in formulas checks tooling lib; do \
	   [ -d "$$d" ] || continue; \
	   mkdir -p "$(CITY)/$$d"; \
	   cp -pR "$$d"/. "$(CITY)/$$d/"; \
	   echo "  synced $$d/"; \
	 done
	@echo "A running workflow keeps the formula it was cooked with."

install-mayor:
	@[ -n "$(CITY)" ] || { echo "make install-mayor CITY=<city-dir>"; exit 64; }
	@[ -d "$(CITY)/agents" ] || { echo "not a city: $(CITY)/agents is not there"; exit 65; }
	@mkdir -p "$(CITY)/agents/mayor"
	@cp agents/mayor/prompt.template.md "$(CITY)/agents/mayor/prompt.template.md"
	@echo "installed. The running mayor keeps its old prompt until:"
	@echo "    gc session reset mayor"

test: ; @./test.sh

clean: ; @rm -rf $(OUT) $(BUNDLES) && echo "cleaned $(OUT)/ and $(BUNDLES)/"

.PHONY: help design compile conformance bundle properties diagram flow brief city-preflight pack-capability pack-diff rules probe demo install-city install-rig install-mayor test selftest clean

selftest:
	@[ -n "$(NAME)" ] || { echo "make selftest NAME=<formula-name>"; exit 64; }
	@set -e; for s in $(OUT)/.gc/scripts/checks/$(NAME)-g*.sh; do \
	   f="$${s%.sh}.fixtures.tsv"; \
	   echo "== $$(basename $$s)"; \
	   tooling/selftest.sh "$$s" "$$f" || true; \
	 done
