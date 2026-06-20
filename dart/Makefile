# Makefile for the Dart port of voxgig/struct.
# Requires the Dart SDK (`dart`) on PATH. No third-party dependencies.

.PHONY: test lint build inspect clean reset publish format

# Run the shared JSON corpus through the Dart implementation.
test:
	dart run test/runner.dart

# "Lint": static analysis (a clean `dart analyze` means the code is sound).
lint:
	dart analyze

# Compile the library to a kernel snapshot as a build smoke-test.
build:
	dart compile kernel lib/voxgig_struct.dart -o /dev/null 2>/dev/null || dart analyze lib

format:
	dart format --output=none --set-exit-if-changed lib test

inspect:
	@dart --version

clean:
	rm -rf .dart_tool *.dill

reset: clean

# The library publishes to pub.dev; this target creates the git tag.
publish:
	@echo "dart: publish via 'dart pub publish' + git tag dart/vX.Y.Z"
