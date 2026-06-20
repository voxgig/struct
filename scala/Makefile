# Makefile for the Scala port of voxgig/struct.
# Requires the Scala 3 compiler (`scalac` / `scala`) and a JDK on PATH.
# No third-party libraries.

SRC = src/voxgig_struct.scala
TESTSRC = $(SRC) test/runner.scala

.PHONY: test lint build inspect clean reset publish

# Build and run the shared JSON corpus through the Scala implementation.
test: build
	scala -cp out Runner

build:
	rm -rf out && mkdir out && scalac $(TESTSRC) -d out

# "Lint": compile the library (a clean compile means the code type-checks).
# scalafmt/scalafix can be wired into this target if available.
lint:
	rm -rf out-lint && mkdir out-lint && scalac $(SRC) -d out-lint && echo ok

inspect:
	@scalac -version 2>&1 | head -1

clean:
	rm -rf out out-lint

reset: clean

# The library publishes to Maven Central; this target creates the git tag.
publish:
	@echo "scala: publish via sbt/Maven Central + git tag scala/vX.Y.Z"
