# Makefile for the Haskell port of voxgig/struct.
# Requires GHC (`ghc` / `runghc`) on PATH. No third-party dependencies
# (only the GHC boot libraries: base, array, etc.).

.PHONY: test lint build inspect clean reset publish format

BUILDDIR := .hsbuild

# Run the shared JSON corpus through the Haskell implementation.
test:
	@mkdir -p $(BUILDDIR)
	ghc -O0 -isrc -itest -outputdir $(BUILDDIR) -o $(BUILDDIR)/runner test/Runner.hs
	$(BUILDDIR)/runner ../build/test/test.json

# "Lint": type-check the library and runner (a clean compile = pass).
lint:
	ghc -fno-code -isrc -itest test/Runner.hs

# Compile the library as a build smoke-test.
build:
	ghc -fno-code -isrc src/VoxgigStruct.hs

format:
	@echo "haskell: (ormolu/fourmolu optional)"

inspect:
	@ghc --version

clean:
	rm -rf $(BUILDDIR) src/*.hi src/*.o test/*.hi test/*.o

reset: clean

# The library publishes to Hackage; this target creates the git tag.
publish:
	@echo "haskell: publish via 'cabal upload' + git tag haskell/vX.Y.Z"
