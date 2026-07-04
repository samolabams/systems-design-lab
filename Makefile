# Systems Design Lab — Make targets (§6).
# A module's Make target == its modules/<slug>/ folder name. Most component
# targets also enable a Compose profile; a few lessons reuse the base stack.

SHELL := /bin/bash
COMPOSE := docker compose
DC := $(COMPOSE)

# Ensure .env exists so compose picks up tunables.
ifeq (,$(wildcard ./.env))
  $(shell cp .env.example .env 2>/dev/null)
endif

.DEFAULT_GOAL := help

# Modules that add services through a Compose profile.
PROFILE_MODULES := replication-failover dns async-queues observability \
				   leader-election-replica-sets event-streaming caching rate-limiting \
				   circuit-breakers partitioning-sharding edge-caching \
				   object-storage message-delivery-semantics \
                   service-discovery sagas vector-store

# Runnable lessons that reuse the base stack instead of adding a Compose profile.
BASE_MODULES := api-gateway load-balancing scaling databases database-scaling api-design

# Runnable lessons backed by a different profile name.
ALIAS_MODULES := multi-region-dr

VALIDATE_MODULES := $(PROFILE_MODULES) $(BASE_MODULES) $(ALIAS_MODULES)

EXTRA_PROFILES := load-balancing-haproxy

.PHONY: help base all validate validate-profile up down reset ps logs scale chaos load smoke $(PROFILE_MODULES) $(BASE_MODULES) $(ALIAS_MODULES) $(EXTRA_PROFILES)

help: ## Show this help.
	@echo "Systems Design Lab — targets:"
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS=":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Runnable modules that add a Compose profile:"
	@printf '  make %s\n' $(PROFILE_MODULES)
	@echo ""
	@echo "Runnable modules that reuse the base stack:"
	@printf '  make %s\n' $(BASE_MODULES) $(ALIAS_MODULES)
	@echo ""
	@echo "Optional contrast profiles:"
	@printf '  make %s\n' $(EXTRA_PROFILES)

base: ## Start the always-on base system (gateway -> app -> pgbouncer -> primary).
	$(DC) up -d --build
	@echo "Gateway: http://localhost:$${GATEWAY_HTTP_PORT:-8080}"

# Generic profile target: `make async-queues` -> base + --profile async-queues.
$(PROFILE_MODULES): ## Start base + the named module profile (e.g. make async-queues).
	$(DC) --profile $@ up -d --build
	@echo "Started base + profile '$@'."

$(BASE_MODULES): ## Start base for lessons that reuse the always-on stack.
	$(DC) up -d --build
	@echo "Started base for module '$@'."

multi-region-dr: ## Start the replication/failover profile used by the DR lesson.
	$(DC) --profile replication-failover up -d --build
	@echo "Started replication-failover profile for module 'multi-region-dr'."

load-balancing-haproxy: ## Start the optional HAProxy contrast for load balancing.
	$(DC) --profile load-balancing-haproxy up -d --build haproxy
	@echo "Started HAProxy contrast. Stats: http://localhost:$${HAPROXY_STATS_PORT:-8404}/stats"

all: ## Start everything (every profile).
	$(DC) $(foreach p,$(PROFILE_MODULES) $(EXTRA_PROFILES),--profile $(p)) up -d --build

validate: ## Start, run, and reset every runnable module sequentially.
	./scripts/validate-modules.sh $(VALIDATE_MODULES)

validate-profile: ## Validate one module: make validate-profile PROFILE=async-queues.
	@test -n "$(PROFILE)" || (echo "usage: make validate-profile PROFILE=async-queues" && exit 1)
	./scripts/validate-modules.sh "$(PROFILE)"

up: base ## Alias for `make base`.

ps: ## Show running services.
	$(DC) ps

logs: ## Tail logs (use S=app to scope to one service).
	$(DC) logs -f $(S)

scale: ## Scale the app tier: make scale N=3.
	@test -n "$(N)" || (echo "usage: make scale N=3" && exit 1)
	$(DC) up -d --scale app=$(N) --no-recreate
	@echo "Scaled app to $(N). Probe distribution: make health-loop"

health-loop: ## Hit /api/health repeatedly to see which instance answers.
	@for i in $$(seq 1 12); do \
		curl -s http://localhost:$${GATEWAY_HTTP_PORT:-8080}/api/health; echo; \
	done

chaos: ## Kill a random running container (failure injection).
	@cid=$$($(DC) ps -q | shuf -n 1); \
	name=$$(docker inspect --format '{{.Name}}' $$cid 2>/dev/null); \
	echo "Killing $$name ($$cid)"; \
	docker kill $$cid

load: ## Run the k6 smoke test through the gateway.
	docker run --rm --network systems-design_frontend -v $$PWD/apps/url-shortener/load:/scripts \
		-e GATEWAY=http://gateway:80 grafana/k6 run /scripts/smoke.js

smoke: load ## Alias for `make load`.

reset: ## Tear everything down and remove volumes (clean slate).
	$(DC) $(foreach p,$(PROFILE_MODULES) $(EXTRA_PROFILES),--profile $(p)) down -v --remove-orphans
