// Universal struct smoke: getpath({ db: { host: "localhost" } }, "db.host").
using Voxgig.Struct;

var store = new Dictionary<string, object?>
{
    ["db"] = new Dictionary<string, object?> { ["host"] = "localhost" },
};

var got = StructUtils.GetPath(store, "db.host");

if (got as string == "localhost")
{
    Console.WriteLine("OK csharp: GetPath(db.host) = localhost");
    return 0;
}

Console.Error.WriteLine($"FAIL csharp: GetPath(db.host) = {got ?? "null"} (want localhost)");
return 1;
