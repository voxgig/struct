.PHONY: inspect build test lint format-check clean reset

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
