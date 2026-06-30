defmodule VoxgigStruct.MixProject do
  use Mix.Project

  # Single source of truth for the version (shared with the Makefile). VERSION
  # is shipped in the package files below so the dep compiles at the consumer.
  @version File.read!("VERSION") |> String.trim()
  @source_url "https://github.com/voxgig/struct"

  def project do
    [
      app: :voxgig_struct,
      version: @version,
      elixir: "~> 1.14",
      name: "voxgig_struct",
      description:
        "A faithful Elixir port of voxgig/struct: utilities for transforming " <>
          "and validating JSON-like data structures.",
      source_url: @source_url,
      package: package(),
      deps: deps()
    ]
  end

  def application, do: []

  # Zero third-party runtime dependencies (by project policy).
  defp deps, do: []

  defp package do
    [
      name: "voxgig_struct",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Voxgig"],
      files: ~w(lib LICENSE README.md mix.exs VERSION)
    ]
  end
end
