// Smoke test for the new Value-based implementation.
// Verifies the foundation compiles and basic primitives work before
// the full corpus runner lands.

#include <iostream>
#include <cassert>

#include "voxgig_struct.hpp"

using namespace voxgig::structlib;

#define CHECK(expr) do { if (!(expr)) { std::cerr << "FAIL: " << #expr << " at " << __LINE__ << "\n"; ok = false; } } while (0)

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

  // keysof preserves insertion order.
  Value ord = jm({"z", 1, "a", 2, "m", 3});
  auto ks = keysof(ord);
  CHECK(ks.size() == 3);
  CHECK(ks[0] == "z");
  CHECK(ks[1] == "a");
  CHECK(ks[2] == "m");

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
  Value walked = walk_v(tree,
      [](const Value&, const Value& v, const Value&, const std::vector<std::string>&) { return v; });
  CHECK(walked == tree);

  // merge.
  Value merged = merge_v(jt({jm({"a", 1, "b", 2}), jm({"b", 3, "c", 4})}));
  CHECK(getprop(merged, Value("a")) == Value(int64_t(1)));
  CHECK(getprop(merged, Value("b")) == Value(int64_t(3)));
  CHECK(getprop(merged, Value("c")) == Value(int64_t(4)));

  std::cout << (ok ? "smoke OK" : "smoke FAILED") << "\n";
  return ok ? 0 : 1;
}
