// Smoke test for the new Value-based implementation.
// Verifies the foundation compiles and basic primitives work before
// the full corpus runner lands.

#include <iostream>
#include <cassert>

#include "value_io.hpp"
#include "voxgig_struct.hpp"

using namespace voxgig::structlib;

#define CHECK(expr)                                                                                \
  do {                                                                                             \
    if (!(expr)) {                                                                                 \
      std::cerr << "FAIL: " << #expr << " at " << __LINE__ << "\n";                                \
      ok = false;                                                                                  \
    }                                                                                              \
  } while (0)

int main() {
  bool ok = true;

  // Sentinels.
  CHECK(SKIP() == SKIP());
  CHECK(DELETE_V() == DELETE_V());
  CHECK(SKIP() != DELETE_V());
  CHECK(is_skip(SKIP()));
  CHECK(is_delete(DELETE_V()));

  // Predicates.
  CHECK(isnode(jm({"a", 1})));
  CHECK(isnode(jt({1, 2, 3})));
  CHECK(!isnode(Value(1)));
  CHECK(ismap(jm({})));
  CHECK(islist(jt({})));
  CHECK(iskey(Value("a")));
  CHECK(iskey(Value(0)));
  CHECK(!iskey(Value("")));
  CHECK(isempty(Value::undef()));
  CHECK(isempty(Value(nullptr)));
  CHECK(isempty(Value("")));
  CHECK(isempty(jm({})));
  CHECK(isempty(jt({})));
  CHECK(!isempty(Value("a")));

  // typify.
  CHECK(typify(Value::undef()) == T_noval);
  CHECK(typify(Value(nullptr)) == (T_scalar | T_null));
  CHECK(typify(Value(true)) == (T_scalar | T_boolean));
  CHECK(typify(Value(int64_t(1))) == (T_scalar | T_number | T_integer));
  CHECK(typify(Value(1.5)) == (T_scalar | T_number | T_decimal));
  CHECK(typify(Value("a")) == (T_scalar | T_string));
  CHECK(typify(jt({})) == (T_node | T_list));
  CHECK(typify(jm({})) == (T_node | T_map));

  // typename.
  CHECK(typename_str(typify(Value("a"))) == "string");
  CHECK(typename_str(typify(jm({}))) == "map");
  CHECK(typename_str(typify(jt({}))) == "list");

  // getprop / setprop.
  Value m = jm({"a", 1, "b", 2});
  CHECK(getprop(m, Value("a")) == Value(int64_t(1)));
  CHECK(getprop(m, Value("missing")) == Value::undef());
  CHECK(getprop(m, Value("missing"), Value("alt")) == Value("alt"));
  setprop(m, Value("c"), Value(3));
  CHECK(getprop(m, Value("c")) == Value(int64_t(3)));

  // Reference stability: copy of m sees the mutation.
  Value m2 = m;
  setprop(m2, Value("d"), Value(4));
  CHECK(getprop(m, Value("d")) == Value(int64_t(4)));

  // Clone breaks the reference.
  Value m3 = clone(m);
  setprop(m3, Value("e"), Value(5));
  CHECK(getprop(m, Value("e")) == Value::undef());

  // keysof returns alphabetically sorted keys (matches TS canonical
  // Object.keys(val).sort()).
  Value ord = jm({"z", 1, "a", 2, "m", 3});
  auto ks = keysof(ord);
  CHECK(ks.size() == 3);
  CHECK(ks[0] == "a");
  CHECK(ks[1] == "m");
  CHECK(ks[2] == "z");

  // Sentinel survives clone.
  Value sk = SKIP();
  Value sk_clone = clone(sk);
  CHECK(is_skip(sk_clone));
  CHECK(sk == sk_clone);

  // pad / stringify / pathify smoke.
  CHECK(pad(Value("a"), 3, "_") == "a__");
  CHECK(pad(Value("abc"), -5, "_") == "__abc");
  CHECK(stringify(Value(int64_t(1))) == "1");
  CHECK(stringify(Value("hi")) == "hi");
  CHECK(pathify(jt({"a", "b"}), 0, 0) == "a.b");
  CHECK(pathify(jt({}), 0, 0) == "<root>");

  // walk identity.
  Value tree = jm({"a", jm({"b", "B"})});
  Value walked = walk_v(tree, [](const Value&, const Value& v, const Value&,
                                 const std::vector<std::string>&) { return v; });
  CHECK(walked == tree);

  // merge.
  Value merged = merge_v(jt({jm({"a", 1, "b", 2}), jm({"b", 3, "c", 4})}));
  CHECK(getprop(merged, Value("a")) == Value(int64_t(1)));
  CHECK(getprop(merged, Value("b")) == Value(int64_t(3)));
  CHECK(getprop(merged, Value("c")) == Value(int64_t(4)));

  // parse_json: malformed input, or anything after the value, gives undef.
  for (const char* bad : {"{\"id\": \"x01\", \"title\": ", "[1, 2] trailing", "{} {}", "[1, 2",
                          "[1 2]", "[1,]", "{\"a\" 1}", "{\"a\": 1,}", "{1: 2}", "nul", "01", "1.",
                          "-", "1e+", "\"open", "\"a\\x\"", "\"tab\there\""}) {
    if (!parse_json(bad).is_undef()) {
      std::cerr << "FAIL: parse_json accepted " << bad << "\n";
      ok = false;
    }
  }
  Value whole = parse_json(" {\"a\": [0, -2.5e3, true, null, \"\\u00e9\"]}\n");
  Value items = getprop(whole, Value("a"));
  CHECK(getprop(items, Value(1)) == Value(-2500.0));
  CHECK(getprop(items, Value(4)) == Value("\xc3\xa9"));

  // Condense: what the corpus cannot express - identity, sharing and immutability.
  const char* csrc = "{\"b\":{\"m\":\"GET\"},\"a\":{\"m\":\"GET\"},\"l\":[1,\"x\",true]}";
  CHECK(jsonify(condense(parse_json(csrc)), 0) == jsonify(condense(parse_json(csrc)), 0));
  CHECK(jsonify(condense(parse_json(csrc)), 0) ==
        jsonify(condense(parse_json(
                    "{\"l\":[1,\"x\",true],\"a\":{\"m\":\"GET\"},\"b\":{\"m\":\"GET\"}}")),
                0));

  auto nodes = [](const char* s) { return size(getprop(condense(parse_json(s)), Value("node"))); };
  int64_t one = nodes("{\"x\":{\"m\":\"GET\",\"p\":\"/1\"}}");
  int64_t two = nodes("{\"x\":{\"m\":\"GET\",\"p\":\"/1\"},\"y\":{\"m\":\"GET\",\"p\":\"/1\"}}");
  CHECK(two == one);
  CHECK(nodes("{\"x\":{\"m\":\"GET\"},\"y\":{\"m\":\"PUT\"},\"z\":{\"m\":\"POST\"}}") > two);

  Value rt = parse_json("{\"a\":{\"b\":[1,\"x\",true,null,{}]},\"c\":\"z\"}");
  CHECK(expand(condense(rt)) == rt);

  Value deep = parse_json("{\"entity\":{\"p\":{\"op\":{\"list\":{\"method\":\"GET\"}}}}}");
  Value cdeep = condense(deep);
  CHECK(getpath_v(cdeep, jt({"entity", "p", "op", "list"})) ==
        getpath_v(deep, jt({"entity", "p", "op", "list"})));
  CHECK(getpath_v(cdeep, jt({"entity", "p", "op", "list", "method"})) == Value("GET"));
  CHECK(getpath_v(cdeep, jt({"entity", "nope"})).is_undef());

  CondenseView v = condenseview(
      condense(parse_json("{\"entity\":{\"a\":{\"v\":1},\"b\":{\"v\":2}},\"other\":9}")));
  CHECK(v.keys(Value("entity")) == std::vector<std::string>({"a", "b"}));
  CHECK(v.at(Value("entity")).at(Value("b")).get(Value("v")) == Value(2));
  CHECK(v.has(Value("entity.a")));
  CHECK(!v.has(Value("entity.zz")));
  CHECK(v.size() == 2);
  CondenseView vz = v.at(Value("entity.zz"));
  CHECK(!vz.exists() && 0 == vz.size() && vz.keys().empty() && vz.value().is_undef() &&
        vz.ref().is_undef());

  CondenseView vs =
      condenseview(condense(parse_json("{\"a\":{\"m\":\"GET\"},\"b\":{\"m\":\"GET\"}}")));
  Value x = vs.get(Value("a"));
  Value y = vs.get(Value("b"));
  CHECK(x == y && x.as_map() != y.as_map());
  setprop(x, Value("m"), Value("MUTATED"));
  CHECK(vs.get(Value("b.m")) == Value("GET"));
  CHECK(vs.at(Value("a")).ref().as_map() == vs.at(Value("a")).ref().as_map());

  Value pv = parse_json("{\"x\":\"__proto__\"}");
  CHECK(expand(condense(pv)) == pv);
  CHECK(jsonify(expand(condense(parse_json("{\"__proto__\":1}"))), 0) == "{\"__proto__\":1}");

  CHECK(getpath_v(condense(parse_json("{\"a\":null}")), Value("a")).is_undef());
  CHECK(getpath_v(parse_json("{\"a\":null}"), Value("a")).is_undef());
  Value bstore = parse_json("{\"base\":{\"x\":1}}");
  Injection binj(Value::undef(), Value::undef());
  binj.base = "base";
  CHECK(getpath_v(condense(bstore), Value("x"), &binj) == Value(1));
  CHECK(getpath_v(bstore, Value("x"), &binj) == Value(1));

  // Unary + would accept these; a plain list read does not, so condensing must not change
  // which value a path selects.
  Value pl = parse_json("{\"l\":[10,20]}");
  Value cl = condense(pl);
  for (const char* k : {"01", "1e0", " 1", "+1", "1.0", "-0"})
    CHECK(getpath_v(cl, jt({"l", k})) == getpath_v(pl, jt({"l", k})));
  CHECK(getpath_v(cl, jt({"l", "1"})) == Value(20));

  Value sym = getprop(condense(parse_json("{\"a\":\"\xF0\x90\x80\x80\",\"b\":\"\xEF\xBF\xBF\"}")),
                      Value("sym"));
  CHECK(getprop(sym, Value(2)) == Value("\xEF\xBF\xBF"));
  CHECK(getprop(sym, Value(3)) == Value("\xF0\x90\x80\x80"));

  Value astral = condense(parse_json("{\"\xEF\xBC\xA1\":1,\"\xF0\x9F\x98\x80\":2}"));
  CHECK(getpath_v(astral, jt({"\xF0\x9F\x98\x80"})) == Value(2));
  CHECK(getpath_v(astral, jt({"\xEF\xBC\xA1"})) == Value(1));
  CHECK(condenseview(astral).get(Value("\xF0\x9F\x98\x80")) == Value(2));

  auto immutable = [](const std::function<void()>& fn) {
    try {
      fn();
    } catch (const std::runtime_error& err) {
      return std::string(err.what()).find("immutable") != std::string::npos;
    }
    return false;
  };
  Value cond = condense(parse_json("{\"a\":1}"));
  CHECK(delprop(cond, Value::undef()).as_map() == cond.as_map());
  CHECK(setprop(cond, Value::undef(), Value(1)).as_map() == cond.as_map());
  CHECK(immutable([&] { delprop(cond, Value("sym")); }));
  CHECK(immutable([&] { setpath_v(cond, Value("a"), Value(2)); }));
  CHECK(immutable([&] { setprop(cond, Value("a"), Value(2)); }));
  Value expanded = expand(cond);
  setpath_v(expanded, Value("a"), Value(2));
  CHECK(getprop(expanded, Value("a")) == Value(2));

  // A checker that throws inside a $NOF or $ALL trial is not a refusal: the error propagates.
  auto boomextra = std::shared_ptr<Map>(new Map());
  boomextra->set("$BOOM",
                 Value(Injector([](Injection&, const Value&, const std::string&,
                                   const Value&) -> Value { throw std::runtime_error("boom"); })));
  auto boomopts = std::shared_ptr<Map>(new Map());
  boomopts->set("extra", Value(boomextra));
  for (const Value& trial : {jt({"`$NOF`", 1, "`$BOOM`"}), jt({"`$ALL`", "`$BOOM`"})}) {
    std::string thrown;
    try {
      validate(jm({"a", 1}), jm({"a", trial}), Value(boomopts));
    } catch (const std::runtime_error& err) {
      thrown = err.what();
    }
    CHECK(thrown == "boom");
  }

  std::cout << (ok ? "smoke OK" : "smoke FAILED") << "\n";
  return ok ? 0 : 1;
}
