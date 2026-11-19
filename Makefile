.PHONY: help lint test check install
help:     ## list targets
	@grep -E '^[a-z]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'
lint:     ## shellcheck every script
	shellcheck bin/*.sh lib/*.sh install.sh
test:     ## run bats test suite
	bats tests/
check: lint test  ## lint + test
install:  ## install to /opt/ops-toolkit (needs sudo)
	sudo ./install.sh
