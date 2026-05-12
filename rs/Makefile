.PHONY: inspect build test clean reset

inspect:
	@echo "Rust toolchain:"
	@rustc --version
	@cargo --version
	@echo ""
	@echo "Project version:"
	@grep '^version' Cargo.toml | head -1

build:
	cargo build

test:
	cargo test

clean:
	cargo clean

reset: clean
	rm -f Cargo.lock
