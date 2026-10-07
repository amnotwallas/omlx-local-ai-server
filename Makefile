SHELL := /bin/zsh

MODEL ?= Qwen3.8-27B-oQ4e-mtp
BASE_URL ?= http://localhost:8000
BREW_PREFIX := $(shell brew --prefix)

.PHONY: help serve start stop restart status check-key models test memory logs version

help:
	@echo "oMLX Local AI Server"
	@echo ""
	@echo "  make serve    Run oMLX in the foreground"
	@echo "  make start    Start the managed oMLX service"
	@echo "  make stop     Stop the managed oMLX service"
	@echo "  make restart  Restart the managed oMLX service"
	@echo "  make status   Show Homebrew service status"
	@echo "  make models   List API models (requires OMLX_API_KEY)"
	@echo "  make test     Run a short inference test (requires OMLX_API_KEY)"
	@echo "  make memory   Show memory pressure and swap usage"
	@echo "  make logs     Follow oMLX logs"
	@echo "  make version  Show oMLX version"

serve:
	omlx serve

start:
	omlx start

stop:
	omlx stop

restart:
	omlx restart

status:
	brew services info omlx

version:
	omlx --version

check-key:
	@test -n "$$OMLX_API_KEY" || \
		(echo "OMLX_API_KEY is not set."; \
		 echo 'Run: read -s "OMLX_API_KEY?oMLX API key: "; echo; export OMLX_API_KEY'; \
		 exit 1)

models: check-key
	@curl -fsS "$(BASE_URL)/v1/models" \
		-H "Authorization: Bearer $$OMLX_API_KEY" \
		| python3 -m json.tool

test: check-key
	@curl -fsS "$(BASE_URL)/v1/chat/completions" \
		-H "Authorization: Bearer $$OMLX_API_KEY" \
		-H "Content-Type: application/json" \
		-d '{"model":"$(MODEL)","messages":[{"role":"user","content":"Reply with exactly: oMLX is working"}],"temperature":0,"max_tokens":32}' \
		| python3 -m json.tool

memory:
	@memory_pressure
	@echo ""
	@sysctl vm.swapusage

logs:
	@touch "$(HOME)/.omlx/logs/server.log" "$(BREW_PREFIX)/var/log/omlx.log"
	tail -F "$(HOME)/.omlx/logs/server.log" "$(BREW_PREFIX)/var/log/omlx.log"
