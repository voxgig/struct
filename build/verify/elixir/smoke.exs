# Universal struct smoke: getpath({ db: { host: "localhost" } }, "db.host").
# The Elixir port stores maps as heap nodes, so build the store with the public
# jm/1 constructor. Mix.install resolves the published voxgig_struct from Hex.
Mix.install([{:voxgig_struct, "~> 0.1"}])

alias Voxgig.Struct

store = Struct.jm(["db", Struct.jm(["host", "localhost"])])
got = Struct.getpath(store, "db.host")

if got == "localhost" do
  IO.puts("OK elixir: getpath(db.host) = localhost")
else
  IO.puts("FAIL elixir: getpath(db.host) = #{inspect(got)} (want localhost)")
  System.halt(1)
end
