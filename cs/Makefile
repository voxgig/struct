.PHONY: inspect build test lint format-check clean reset audit

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
