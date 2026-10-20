# SUBDIRS := $(dir $(shell find -name kustomization.yaml -not -path "./bgo1-test/*test*/*"))
SUBDIRS := ./bgo1-test/uit-web-stage ./base/uit-web

.PHONY: help
help:
	@awk 'BEGIN {FS = ":.*?## "} /^[0-9a-zA-Z_-]+:.*?## / {sub("\\\\n",sprintf("\n%22c"," "), $$2);printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: all
all: verify-kustomization validate yamllint      ## Run verify-kustomization, validate and yamllint

.PHONY: verify-kustomization
verify-kustomization: $(SUBDIRS) ## Make sure all kustomization.yaml's include all files in the same directory

.PHONY: yamllint
yamllint: ## Check all yaml files for proper formatting
#	@yamllint .
	yamllint $(SUBDIRS)

.PHONY: $(SUBDIRS)
$(SUBDIRS):
	@cd $@ && for f in *.yaml; do [ "$$f" = "kustomization.yaml" ] && continue; grep -q "$$f" kustomization.yaml && continue; echo "$$f missing in kustomization.yaml in $@"; exit 1; done
	cd $@ && kustomize build -o /dev/null

.PHONY: validate
validate: ## Run extensive validation on generated manifests
	./tools/validate.sh -d bgo1-test/uit-web-stage

# vim: syntax=make noexpandtab

