.PHONY: inspect build test lint clean reset

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

# perlcritic is the de-facto Perl linter.
lint:
	@if command -v perlcritic >/dev/null 2>&1; then \
		perlcritic --gentle lib t; \
	else \
		echo "perlcritic not installed — skipping lint"; \
	fi

clean:
	@find . -name '*.bak' -delete

reset: clean
