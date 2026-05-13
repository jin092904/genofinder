SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

COMPOSE := docker compose -f infra/compose/docker-compose.dev.yml

.PHONY: help dev down logs ps test test-api test-workers test-web lint lint-py lint-js fmt security-scan migrate alembic-rev clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

dev: ## docker-compose 전체 기동 (Postgres/Redis/Qdrant/OpenSearch/Ollama/LocalStack KMS)
	$(COMPOSE) up -d --build
	@echo "API:        http://localhost:8000"
	@echo "Web:        http://localhost:3000"
	@echo "Postgres:   localhost:5432"
	@echo "Qdrant:     http://localhost:6333"
	@echo "OpenSearch: http://localhost:9200"
	@echo "Ollama:     INTERNAL ONLY (not host-published per ADR 0003)"

down: ## docker-compose stop + remove
	$(COMPOSE) down

logs: ## docker-compose 전체 로그 follow
	$(COMPOSE) logs -f --tail=200

ps: ## docker-compose 현황
	$(COMPOSE) ps

test: test-api test-workers test-web ## 전체 테스트

test-api:
	cd apps/api && uv run pytest

test-workers:
	cd apps/workers && uv run pytest

test-web:
	cd apps/web && pnpm test

lint: lint-py lint-js ## 전체 lint

lint-py:
	cd apps/api && uv run ruff check . && uv run mypy src
	cd apps/workers && uv run ruff check . && uv run mypy src

lint-js:
	cd apps/web && pnpm lint && pnpm typecheck

fmt: ## 자동 포맷팅
	cd apps/api && uv run ruff format .
	cd apps/workers && uv run ruff format .
	cd apps/web && pnpm format

security-scan: ## pip-audit + npm audit + trivy fs + gitleaks
	cd apps/api && uv run pip-audit || true
	cd apps/workers && uv run pip-audit || true
	cd apps/web && pnpm audit --audit-level=critical || true
	command -v trivy >/dev/null && trivy fs --severity CRITICAL,HIGH . || echo "trivy not installed"
	command -v gitleaks >/dev/null && gitleaks detect --source . --no-banner || echo "gitleaks not installed"

migrate: ## Alembic 마이그레이션 적용
	cd apps/api && uv run alembic upgrade head

alembic-rev: ## 새 Alembic revision 생성 (NAME=... 필수)
	@test -n "$(NAME)" || (echo "Usage: make alembic-rev NAME=<short_name>"; exit 1)
	cd apps/api && uv run alembic revision --autogenerate -m "$(NAME)"

clean:
	find . -type d \( -name __pycache__ -o -name .pytest_cache -o -name .mypy_cache -o -name .ruff_cache \) -prune -exec rm -rf {} +
	rm -rf apps/web/.next apps/web/out
