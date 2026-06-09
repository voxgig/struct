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
publish: test
	rm -rf .release && mkdir -p .release
	cp -r lib t Makefile.PL .release/
	@[ -f README.md ] && cp README.md .release/ || true
	cd .release && $(PERL) Makefile.PL && make manifest && make dist && cpan-upload *.tar.gz
	@if git rev-parse -q --verify "refs/tags/perl/v$(VERSION)" >/dev/null; then echo "tag perl/v$(VERSION) already exists — bump $$VERSION in lib/Voxgig/Struct.pm first"; exit 1; fi
	git tag -a "perl/v$(VERSION)" -m "perl v$(VERSION)"
	git push origin "perl/v$(VERSION)"
