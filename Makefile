SERVICES := orders-api worker web
.PHONY: lint test up down logs tf-fmt tf-validate helm-lint

lint:            ## Lint Python services
	ruff check services && ruff format --check services

test:            ## Run unit tests for all services
	@for s in $(SERVICES); do echo "== $$s"; (cd services/$$s && python -m pytest -q) || exit 1; done

up:              ## Start the local stack (http://localhost:8000)
	docker compose up --build -d

down:            ## Stop the local stack and delete data
	docker compose down -v

logs:
	docker compose logs -f orders-api worker

tf-fmt:
	terraform fmt -recursive infra/terraform

tf-validate:
	cd infra/terraform/envs/dev && terraform init -backend=false -input=false && terraform validate

helm-lint:
	@for s in $(SERVICES); do helm lint deploy/charts/microservice --set nameOverride=$$s -f deploy/envs/dev/global.yaml -f deploy/envs/dev/$$s.yaml || exit 1; done
