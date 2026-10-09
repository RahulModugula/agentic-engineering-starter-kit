.PHONY: help check test scan mutate verify lint hooks install-dry
help:                       ## list the targets
	@grep -E '^[a-z-]+:.*## ' Makefile | sed -E 's/:[^#]*## /\t/' | awk -F'\t' '{printf "  make %-12s %s\n", $$1, $$2}'

check: test scan            ## what every commit needs: all tests + the secret/PII scan (about a minute)

test:                       ## unit + end-to-end tests; each proves its rule fires AND stays quiet on look-alikes
	/bin/bash tests/run.sh

scan:                       ## secrets, personal data, session state: working tree AND full git history
	/bin/bash bin/scan.sh --history .

mutate:                     ## break every safety rule on purpose (tests/mutants.txt); each must turn a test red
	python3 tests/mutate.py

verify: check mutate lint   ## the full bar before a release or a share

lint:                       ## shellcheck + bash/zsh syntax (shellcheck optional: brew install shellcheck)
	@for f in bin/*.sh claude/hooks/*.sh tests/*.sh install.sh; do bash -n "$$f" || exit 1; done
	@zsh -n claude/lanes.zsh
	@if command -v shellcheck >/dev/null; then shellcheck -S warning bin/*.sh claude/hooks/*.sh install.sh; \
	 else echo "shellcheck not installed; syntax checked only"; fi
	@python3 -m py_compile bin/*.py tests/*.py && echo "lint ok"

hooks:                      ## run the scan before every commit in this repo
	git config core.hooksPath .githooks

install-dry:                ## what install.sh would change in ~/.claude (changes nothing)
	/bin/bash install.sh
