.PHONY: inspect build test lint clean reset publish

PERL ?= perl

inspect:
	@echo "Perl version:"
	@$(PERL) -e 'print "$$]\n"'
	@echo ""
	@echo "Project version:"
	@$(PERL) -e 'use Voxgig::Struct; print "$$Voxgig::Struct::VERSION\n"' -Ilib

# No build step — pure-Perl module.
build:
	@echo "No build step for Perl"

test:
	prove -Ilib t/

# perlcritic is the de-facto Perl linter. Local soft-skip when not on
# PATH; CI hardens this via the `CI=true` env var GitHub Actions sets.
lint:
	@if command -v perlcritic >/dev/null 2>&1; then \
		perlcritic --gentle lib t; \
	elif [ "$$CI" = "true" ]; then \
		echo "perlcritic not installed (required in CI)"; exit 1; \
	else \
		echo "perlcritic not installed — skipping lint"; \
	fi

clean:
	@find . -name '*.bak' -delete

reset: clean

# Release: build a CPAN dist and upload to PAUSE, then tag perl/vX.Y.Z
# (version from $VERSION in lib/Voxgig/Struct.pm).
#
# Auth: `cpan-upload` reads PAUSE credentials from ~/.pause
#   (user PAUSE_ID / password SECRET). See `man cpan-upload`.
#
# ExtUtils::MakeMaker's `perl Makefile.PL` generates a file called
# `Makefile`, which would OVERWRITE this hand-written Makefile. So we
# copy the dist sources into a throwaway .release/ dir and build there.
VERSION := $(shell $(PERL) -Ilib -MVoxgig::Struct -e 'print $$Voxgig::Struct::VERSION')
TAG := perl/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump $$VERSION in lib/Voxgig/Struct.pm first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would publish dist and tag $(TAG); nothing pushed."; \
	  exit 0; \
	fi; \
	rm -rf .release && mkdir -p .release; \
	cp -r lib t Makefile.PL .release/; \
	{ [ -f README.md ] && cp README.md .release/ || true; }; \
	cd .release && $(PERL) Makefile.PL && make manifest && make dist && cpan-upload *.tar.gz; \
	cd ..; \
	git tag -a "$(TAG)" -m "perl v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published dist + tag $(TAG)."
