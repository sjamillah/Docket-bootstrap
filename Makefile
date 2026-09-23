# One flat template, so there is nothing to package. Lint is the whole check.
.PHONY: lint

lint:
	cfn-lint bootstrap.yaml
