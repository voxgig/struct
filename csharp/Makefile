.PHONY: inspect build test lint format-check clean reset audit publish

inspect:
	@echo ".NET SDK version:"
	@dotnet --version

build:
	dotnet build VoxgigStruct.csproj

test:
	dotnet test tests/VoxgigStructTest.csproj

# Code quality: Roslyn analyzers (run as part of build, warnings-as-info) +
# `dotnet format` style verification.
lint:
	dotnet build VoxgigStruct.csproj -warnaserror -nologo
	dotnet format VoxgigStruct.csproj --verify-no-changes --severity warn

format-check:
	dotnet format VoxgigStruct.csproj --verify-no-changes --severity warn

clean:
	dotnet clean VoxgigStruct.csproj 2>/dev/null || true
	rm -rf bin obj tests/bin tests/obj

reset: clean

# Supply-chain: fail on any NuGet dependency with a known vulnerability.
audit:
	dotnet restore tests/VoxgigStructTest.csproj >/dev/null
	@out=$$(dotnet list tests/VoxgigStructTest.csproj package --vulnerable --include-transitive 2>&1); \
	echo "$$out"; \
	if echo "$$out" | grep -q "has the following vulnerable packages"; then exit 1; fi

# Release: publish to NuGet, then tag csharp/vX.Y.Z (version from the csproj).
# Needs NuGet auth (NUGET_API_KEY env var).
VERSION := $(shell grep -m1 "<Version>" VoxgigStruct.csproj | sed -E "s/.*<Version>([^<]+)<.*/\1/")
TAG := csharp/v$(VERSION)
AQL_DRY_RUN_FILLER := AQL-DRY-RUN-FILLER-NOT-A-REAL-SECRET
publish: test
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null; then \
	  echo "tag $(TAG) already exists — bump csproj first"; exit 1; fi
	@set -e; \
	token="$${GITHUB_TOKEN:-$$GH_TOKEN}"; \
	if [ "$$token" = "$(AQL_DRY_RUN_FILLER)" ]; then \
	  echo "[dry-run] aql filler token detected: would publish package and tag $(TAG); nothing pushed."; \
	  exit 0; \
	fi; \
	dotnet pack -c Release; \
	dotnet nuget push bin/Release/*.nupkg --source https://api.nuget.org/v3/index.json --api-key $$NUGET_API_KEY; \
	git tag -a "$(TAG)" -m "csharp v$(VERSION)"; \
	if [ -n "$$token" ]; then \
	  hdr="AUTHORIZATION: basic $$(printf 'x-access-token:%s' "$$token" | base64 | tr -d '\n')"; \
	  git -c http.extraheader="$$hdr" push https://github.com/voxgig/struct.git "$(TAG)"; \
	else \
	  git push origin "$(TAG)"; \
	fi; \
	echo "Published package + tag $(TAG)."
