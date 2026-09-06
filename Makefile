.PHONY: pipeline clean validate test help

PIPELINE_DIR := redhat/rhoai/v3.5/base/03-workloads/fine-tuning-demo/pipeline
PIPELINES_COMPONENTS ?= ../pipelines-components

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

pipeline: ## Compile pipeline and generate GitOps CRs
	@echo "=== Compiling pipeline ==="
	cd $(PIPELINE_DIR) && PIPELINES_COMPONENTS_PATH=$(abspath $(PIPELINES_COMPONENTS)) python3 finetuning_pipeline.py
	@echo ""
	@echo "=== Generating GitOps CRs ==="
	cd $(PIPELINE_DIR) && PIPELINES_COMPONENTS_PATH=$(abspath $(PIPELINES_COMPONENTS)) python3 build_pipeline.py
	@echo ""
	@echo "=== Done. Review changes and push: ==="
	@echo "  git add -A && git commit -m 'Update pipeline' && git push"

validate: ## Validate config and dry-run
	cd $(PIPELINE_DIR) && python3 build_pipeline.py --dry-run

clean: ## Remove compiled artifacts
	rm -f $(PIPELINE_DIR)/finetuning_pipeline.yaml

test: ## Run pipeline unit tests
	cd $(PIPELINE_DIR)/local_components && python3 -m pytest shared/tests/ -v --tb=short
