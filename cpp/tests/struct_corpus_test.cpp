// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
//
// Voxgig Struct — the shared corpus, run on the shared runner.
//
// The in-situ runner (tests/runner.hpp) is gone. Every group is driven through
// voxgig/omni, so this file only says WHICH subject answers each group and
// with which flags — the entry loop, the comparison, the `err` and `match`
// handling all live in the runner, identically for every port.
//
// Flags mirror canonical: typescript/test/utility/StructUtility.test.ts.

#include <cstdio>
#include <iostream>
#include <string>
#include <vector>

#include "omni_bridge.hpp"
#include "value.hpp"
#include "voxgig_struct.hpp"

using namespace voxgig::structlib;
using bridge::Subject;

namespace {

const std::string NULLMARK = "__NULL__";

omni::Json SPEC;
std::unique_ptr<omni::RunPack> PACK;

int GROUPS = 0;
int FAILED = 0;

// Run one group. Each group is one assertion: omni stops at its first failing
// entry and reports the index, the entry and both values.
void run(const std::string& category, const std::string& name, bool donull, const Subject& s) {
  const std::string label = category + "." + name;
  omni::Flags flags = donull ? omni::Flags() : omni::Flags::nonull();
  flags.name = label;

  GROUPS++;
  try {
    PACK->runsetflags_args(SPEC.get(category).get(name), flags, bridge::wrap(s));
    std::printf("  ok   %s\n", label.c_str());
  } catch (const std::exception& err) {
    FAILED++;
    std::printf("  FAIL %s\n       %s\n", label.c_str(), err.what());
  }
}

// `merge.basic`, `inject.basic` and `transform.basic` are single entries, not
// sets, so the runner cannot drive them. Compared here, through omni's own
// deepequal so the rule is the one every group uses.
void single(const std::string& label, const omni::Json& entry, const Value& got) {
  const omni::Json want = entry.get("out");
  const omni::Json have = bridge::toomni(got);

  GROUPS++;
  if (omni::deepequal(have, want)) {
    std::printf("  ok   %s\n", label.c_str());
  } else {
    FAILED++;
    std::printf("  FAIL %s\n       expected: %s\n       actual:   %s\n", label.c_str(),
                omni::stringify(want).c_str(), omni::stringify(have).c_str());
  }
}

// Extract a named field from a test-spec object. This mirrors the canonical
// runner's raw JS property access (`vin.val`): a present-but-null field yields
// JSON null, an absent field yields undefined. We therefore use the
// null-preserving lookup_v rather than the Group A getprop/haskey (which would
// drop a stored null and corrupt the test input).
inline Value getp(const Value& in, const std::string& k) {
  return lookup_v(in, Value(k));
}
inline Value getpDef(const Value& in, const std::string& k, const Value& def) {
  return lookup_v(in, Value(k)).is_undef() ? def : lookup_v(in, Value(k));
}

// The runner encodes "value is JSON null" as this marker so it survives a JSON
// round trip; a modifier puts a real null back as the structure is built.
// Mirrors typescript/test/runner.ts:nullModifier — a slot whose injected value
// is exactly the marker becomes JSON null; a string that merely *contains* it
// has the marker rewritten to the literal text "null".
inline void null_modifier(const Value& val, const Value& key, const Value& parent, Injection&,
                          const Value&) {
  if (!val.is_string())
    return;
  const std::string& s = val.as_string();
  if (s == NULLMARK) {
    setprop(parent, key, Value(nullptr));
    return;
  }
  if (s.find(NULLMARK) != std::string::npos) {
    std::string out = s;
    std::string::size_type pos = 0;
    while ((pos = out.find(NULLMARK, pos)) != std::string::npos) {
      out.replace(pos, NULLMARK.size(), "null");
      pos += 4;
    }
    setprop(parent, key, Value(out));
  }
}

} // namespace

int main() {
  try {
    omni::Runner runner = omni::makeRunner("../build/test/test.json");
    PACK = std::make_unique<omni::RunPack>(runner.runner("struct"));
    SPEC = PACK->spec;
  } catch (const std::exception& err) {
    std::cerr << "struct: " << err.what() << "\n";
    return 1;
  }

  std::printf("\n===== struct corpus =====\n");

  // ===== minor =====
  run("minor", "isnode", true, [](const Value& in) { return Value(isnode(in)); });
  run("minor", "ismap", true, [](const Value& in) { return Value(ismap(in)); });
  run("minor", "islist", true, [](const Value& in) { return Value(islist(in)); });
  run("minor", "iskey", false, [](const Value& in) { return Value(iskey(in)); });
  run("minor", "strkey", false, [](const Value& in) { return Value(strkey(in)); });
  run("minor", "isempty", false, [](const Value& in) { return Value(isempty(in)); });
  run("minor", "isfunc", true, [](const Value& in) { return Value(isfunc(in)); });
  run("minor", "getprop", false, [](const Value& in) {
    Value alt = getpDef(in, "alt", Value::undef());
    return alt.is_undef() ? getprop(getp(in, "val"), getp(in, "key"))
                          : getprop(getp(in, "val"), getp(in, "key"), alt);
  });
  run("minor", "getelem", false, [](const Value& in) {
    Value alt = getpDef(in, "alt", Value::undef());
    return alt.is_undef() ? getelem(getp(in, "val"), getp(in, "key"))
                          : getelem(getp(in, "val"), getp(in, "key"), alt);
  });
  run("minor", "clone", false, [](const Value& in) { return clone(in); });
  run("minor", "items", true, [](const Value& in) { return items_v(in); });
  run("minor", "keysof", true, [](const Value& in) {
    auto out = std::make_shared<List>();
    for (const auto& k : keysof(in))
      out->push_back(Value(k));
    return Value(out);
  });
  run("minor", "haskey", false,
      [](const Value& in) { return Value(haskey(getp(in, "src"), getp(in, "key"))); });
  run("minor", "setprop", true, [](const Value& in) {
    Value parent = getpDef(in, "parent", Value::undef());
    if (parent.is_undef())
      parent = Value(nullptr);
    return setprop(parent, getp(in, "key"), getp(in, "val"));
  });
  run("minor", "delprop", true, [](const Value& in) {
    Value parent = getpDef(in, "parent", Value::undef());
    if (parent.is_undef())
      parent = Value(nullptr);
    return delprop(parent, getp(in, "key"));
  });
  run("minor", "stringify", true, [](const Value& in) {
    Value val = getpDef(in, "val", Value::undef());
    // Canonical subject: a stored-null (the NULLMARK in null mode) stringifies
    // as the literal text "null".
    if (val.is_string() && val.as_string() == NULLMARK)
      val = Value("null");
    Value max = getp(in, "max");
    int m = max.is_int() ? static_cast<int>(max.as_int()) : -1;
    return Value(stringify(val, m));
  });
  run("minor", "jsonify", false, [](const Value& in) {
    Value val = getp(in, "val");
    Value flags = getp(in, "flags");
    return Value(jsonify(val, flags));
  });
  run("minor", "pathify", true, [](const Value& in) {
    // Canonical subject: a stored-null path becomes undefined; a stored-null
    // path *element* (the marker) is stripped from the rendered string; and a
    // wholly-null path renders "<unknown-path:null>".
    Value path = getpDef(in, "path", Value::undef());
    bool path_was_null = path.is_string() && path.as_string() == NULLMARK;
    if (path_was_null)
      path = Value::undef();
    Value from = getp(in, "from");
    Value to = getp(in, "to");
    int f = from.is_int() ? static_cast<int>(from.as_int()) : 0;
    int t = to.is_int() ? static_cast<int>(to.as_int()) : 0;
    std::string s = pathify(path, f, t);
    std::string::size_type pos = s.find("__NULL__.");
    if (pos != std::string::npos)
      s.erase(pos, std::string("__NULL__.").size());
    if (path_was_null)
      for (pos = 0; (pos = s.find('>', pos)) != std::string::npos; pos += 6)
        s.replace(pos, 1, ":null>");
    return Value(s);
  });
  run("minor", "escre", true, [](const Value& in) { return Value(escre(in)); });
  run("minor", "escurl", true, [](const Value& in) { return Value(escurl(in)); });
  run("minor", "join", false, [](const Value& in) {
    Value val = getp(in, "val");
    Value sep = getp(in, "sep");
    Value url = getp(in, "url");
    return Value(join(val, sep, url));
  });
  run("minor", "flatten", true, [](const Value& in) {
    Value val = getp(in, "val");
    Value depth = getp(in, "depth");
    int d = depth.is_int() ? static_cast<int>(depth.as_int()) : 1;
    return flatten(val, d);
  });
  run("minor", "filter", true, [](const Value& in) {
    Value val = getp(in, "val");
    std::string check = getp(in, "check").is_string() ? getp(in, "check").as_string() : "";
    ItemCheck pred;
    if (check == "gt3") {
      pred = [](const Value& pair) {
        Value v = getprop(pair, Value(int64_t(1)));
        return v.is_number() && v.as_double() > 3;
      };
    } else {
      pred = [](const Value& pair) {
        Value v = getprop(pair, Value(int64_t(1)));
        return v.is_number() && v.as_double() < 3;
      };
    }
    return filter(val, pred);
  });
  run("minor", "typename", true, [](const Value& in) {
    if (in.is_int())
      return Value(typename_str(static_cast<int>(in.as_int())));
    return Value(typename_str(in));
  });
  run("minor", "typify", false,
      [](const Value& in) { return Value(static_cast<int64_t>(typify(in))); });
  run("minor", "size", false,
      [](const Value& in) -> Value { return Value(voxgig::structlib::size(in)); });
  run("minor", "slice", false, [](const Value& in) {
    Value val = getp(in, "val");
    Value start = getp(in, "start");
    Value end = getp(in, "end");
    return slice(val, start, end);
  });
  run("minor", "pad", false, [](const Value& in) {
    Value val = getp(in, "val");
    Value p = getp(in, "pad");
    Value c = getp(in, "char");
    return Value(pad(val, p, c));
  });
  run("minor", "setpath", false, [](const Value& in) {
    Value store = getp(in, "store");
    Value path = getp(in, "path");
    Value val = getp(in, "val");
    return setpath_v(store, path, val);
  });

  // ===== walk =====
  // `walk.log` is a single entry, not a set, and carries THREE expected
  // sequences - before, after and both - one per callback configuration.
  // It was not run here at all, while DOCS.md claimed every non-condense
  // group was covered; a callback-ordering regression could not have failed
  // this suite. Canonical drives all three (javascript/test/struct.test.js
  // `walk-log`), so this does too.
  {
    const omni::Json entry = SPEC.get("walk").get("log");
    const Value win = bridge::tostruct(entry.get("in"));
    std::vector<std::string> log;
    auto walklog = [&log](const Value& key, const Value& val, const Value& parent,
                          const std::vector<std::string>& path) -> Value {
      auto pv = std::make_shared<List>();
      for (const auto& seg : path)
        pv->push_back(Value(seg));
      log.push_back("k=" + stringify(key) + ", v=" + stringify(val) + ", p=" + stringify(parent) +
                    ", t=" + pathify(Value(pv)));
      return val;
    };
    auto logged = [&log]() {
      auto out = std::make_shared<List>();
      for (const auto& line : log)
        out->push_back(Value(line));
      return Value(out);
    };

    log.clear();
    walk_v(win, nullptr, walklog, MAXDEPTH);
    single("walk.log/after", omni::Json::map({{"out", entry.get("out").get("after")}}), logged());

    log.clear();
    walk_v(win, walklog);
    single("walk.log/before", omni::Json::map({{"out", entry.get("out").get("before")}}), logged());

    log.clear();
    walk_v(win, walklog, walklog, MAXDEPTH);
    single("walk.log/both", omni::Json::map({{"out", entry.get("out").get("both")}}), logged());
  }

  run("walk", "basic", true, [](const Value& in) {
    return walk_v(in,
                  [](const Value& key, const Value& val, const Value&,
                     const std::vector<std::string>& path) -> Value {
                    if (val.is_string()) {
                      std::string out = val.as_string() + "~";
                      for (size_t i = 0; i < path.size(); i++) {
                        if (i > 0)
                          out += ".";
                        out += path[i];
                      }
                      return Value(out);
                    }
                    return val;
                  });
  });
  run("walk", "depth", false, [](const Value& in) {
    Value src = getp(in, "src");
    Value md = getp(in, "maxdepth");
    int maxdepth = md.is_int() ? static_cast<int>(md.as_int()) : MAXDEPTH;
    Value top = Value::undef();
    Value cur = Value::undef();
    auto do_walk = [&](const Value& key, const Value& val, const Value&,
                       const std::vector<std::string>& path) -> Value {
      if (key.is_undef() || isnode(val)) {
        Value child = val.is_list() ? Value(std::make_shared<List>())
                                    : Value(std::shared_ptr<Map>(new Map()));
        if (key.is_undef()) {
          top = child;
          cur = child;
        } else {
          setprop(cur, key, child);
          cur = child;
        }
      } else {
        setprop(cur, key, val);
      }
      return val;
    };
    walk_v(src, do_walk, nullptr, maxdepth);
    return top;
  });
  run("walk", "copy", true, [](const Value& in) {
    std::vector<Value> cur(64);
    auto do_walk = [&](const Value& key, const Value& val, const Value&,
                       const std::vector<std::string>& path) -> Value {
      if (key.is_undef()) {
        cur[0] = val.is_map()    ? Value(std::shared_ptr<Map>(new Map()))
                 : val.is_list() ? Value(std::make_shared<List>())
                                 : val;
        return val;
      }
      Value v = val;
      size_t i = path.size();
      if (isnode(v)) {
        v = v.is_map() ? Value(std::shared_ptr<Map>(new Map())) : Value(std::make_shared<List>());
        cur[i] = v;
      }
      setprop(cur[i - 1], key, v);
      return val;
    };
    walk_v(in, do_walk);
    return cur[0];
  });

  // ===== merge =====
  {
    const omni::Json entry = SPEC.get("merge").get("basic");
    single("merge.basic", entry, merge_v(bridge::tostruct(entry.get("in"))));
  }
  run("merge", "cases", true, [](const Value& in) { return merge_v(in); });
  run("merge", "array", true, [](const Value& in) { return merge_v(in); });
  run("merge", "integrity", true, [](const Value& in) { return merge_v(in); });
  run("merge", "depth", true, [](const Value& in) {
    Value val = getp(in, "val");
    Value depth = getp(in, "depth");
    int d = depth.is_int() ? static_cast<int>(depth.as_int()) : MAXDEPTH;
    return merge_v(val, d);
  });

  // ===== getpath =====
  run("getpath", "basic", true,
      [](const Value& in) { return getpath_v(getp(in, "store"), getp(in, "path")); });
  run("getpath", "relative", true, [](const Value& in) {
    Injection inj(Value::undef(), Value::undef());
    if (haskey(in, Value("dparent")))
      inj.dparent = getp(in, "dparent");
    if (haskey(in, Value("dpath"))) {
      Value dp = getp(in, "dpath");
      inj.dpath.clear();
      if (dp.is_list()) {
        for (const auto& p : *dp.as_list())
          inj.dpath.push_back(strkey(p));
      } else if (dp.is_string()) {
        // Split on '.'.
        const std::string& s = dp.as_string();
        size_t pos = 0;
        while (pos <= s.size()) {
          size_t dot = s.find('.', pos);
          if (dot == std::string::npos) {
            inj.dpath.push_back(s.substr(pos));
            break;
          }
          inj.dpath.push_back(s.substr(pos, dot - pos));
          pos = dot + 1;
        }
      }
    }
    if (haskey(in, Value("base"))) {
      Value b = getp(in, "base");
      if (b.is_string())
        inj.base = b.as_string();
    }
    bool any =
        haskey(in, Value("dparent")) || haskey(in, Value("dpath")) || haskey(in, Value("base"));
    return getpath_v(getp(in, "store"), getp(in, "path"), any ? &inj : nullptr);
  });
  run("getpath", "special", true, [](const Value& in) {
    Value injv = getp(in, "inj");
    if (!injv.is_map())
      return getpath_v(getp(in, "store"), getp(in, "path"));
    Injection inj(Value::undef(), Value::undef());
    Value k = getp(injv, "key");
    if (k.is_string())
      inj.key = k.as_string();
    Value m = getp(injv, "meta");
    if (m.is_map())
      inj.meta = m.as_map();
    Value dp = getp(injv, "dparent");
    if (!dp.is_undef())
      inj.dparent = dp;
    Value dpa = getp(injv, "dpath");
    if (dpa.is_list()) {
      inj.dpath.clear();
      for (const auto& p : *dpa.as_list())
        inj.dpath.push_back(strkey(p));
    }
    return getpath_v(getp(in, "store"), getp(in, "path"), &inj);
  });

  // The handler resolves a `$`-prefixed store entry that is a FUNCTION: the
  // store holds `$FOO`, and the handler calls it. Nothing else in the corpus
  // exercises `Injection::handler`.
  run("getpath", "handler", true, [](const Value& in) {
    auto store = std::shared_ptr<Map>(new Map());
    store->set("$TOP", getp(in, "store"));
    store->set("$FOO", Value(Injector([](Injection&, const Value&, const std::string&,
                                         const Value&) { return Value(std::string("foo")); })));

    Injection inj(Value::undef(), Value::undef());
    inj.handler = [](Injection& cinj, const Value& val, const std::string& ref,
                     const Value& cstore) -> Value {
      return val.is_injector() ? val.as_injector()(cinj, val, ref, cstore) : val;
    };

    return getpath_v(Value(store), getp(in, "path"), &inj);
  });

  // ===== inject =====
  {
    const omni::Json entry = SPEC.get("inject").get("basic");
    const Value in = bridge::tostruct(entry.get("in"));
    single("inject.basic", entry, inject(getp(in, "val"), getp(in, "store")));
  }
  run("inject", "string", true, [](const Value& in) {
    // Canonical subject passes { modify: nullModifier }: an injected stored-null
    // (the marker, in null mode) renders as the literal text "null".
    Injection inj(Value::undef(), Value::undef());
    inj.modify = null_modifier;
    return inject(getp(in, "val"), getp(in, "store"), &inj);
  });
  run("inject", "deep", true,
      [](const Value& in) { return inject(getp(in, "val"), getp(in, "store")); });

  // ===== transform =====
  {
    const omni::Json entry = SPEC.get("transform").get("basic");
    const Value in = bridge::tostruct(entry.get("in"));
    single("transform.basic", entry, transform(getp(in, "data"), getp(in, "spec")));
  }
  run("transform", "paths", true,
      [](const Value& in) { return transform(getp(in, "data"), getp(in, "spec")); });
  run("transform", "cmds", true,
      [](const Value& in) { return transform(getp(in, "data"), getp(in, "spec")); });
  run("transform", "each", true,
      [](const Value& in) { return transform(getp(in, "data"), getp(in, "spec")); });
  run("transform", "pack", true,
      [](const Value& in) { return transform(getp(in, "data"), getp(in, "spec")); });
  run("transform", "modify", true, [](const Value& in) {
    auto opts = std::shared_ptr<Map>(new Map());
    Modify mod = [](const Value& val, const Value& key, const Value& parent, Injection& inj,
                    const Value& store) {
      if (!key.is_undef() && parent.is_map() && val.is_string()) {
        parent.as_map()->set(strkey(key), Value("@" + val.as_string()));
      }
    };
    opts->set("modify", Value(mod));
    return transform(getp(in, "data"), getp(in, "spec"), Value(opts));
  });
  run("transform", "ref", true,
      [](const Value& in) { return transform(getp(in, "data"), getp(in, "spec")); });
  run("transform", "format", false,
      [](const Value& in) { return transform(getp(in, "data"), getp(in, "spec")); });
  run("transform", "apply", true, [](const Value& in) {
    auto opts = std::shared_ptr<Map>(new Map());
    auto extra = std::shared_ptr<Map>(new Map());
    Injector apply_fn = [](Injection&, const Value& val, const std::string&,
                           const Value&) -> Value {
      if (val.is_string()) {
        std::string s = val.as_string();
        for (auto& c : s)
          c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        return Value(s);
      }
      return val;
    };
    extra->set("apply", Value(apply_fn));
    opts->set("extra", Value(extra));
    return transform(getp(in, "data"), getp(in, "spec"), Value(opts));
  });

  // ===== validate =====
  run("validate", "basic", false,
      [](const Value& in) { return validate(getp(in, "data"), getp(in, "spec")); });
  run("validate", "child", true,
      [](const Value& in) { return validate(getp(in, "data"), getp(in, "spec")); });
  run("validate", "one", true,
      [](const Value& in) { return validate(getp(in, "data"), getp(in, "spec")); });
  run("validate", "exact", true,
      [](const Value& in) { return validate(getp(in, "data"), getp(in, "spec")); });
  run("validate", "invalid", false,
      [](const Value& in) { return validate(getp(in, "data"), getp(in, "spec")); });
  run("validate", "special", true, [](const Value& in) {
    Value inj_v = getp(in, "inj");
    return inj_v.is_map() ? validate(getp(in, "data"), getp(in, "spec"), inj_v)
                          : validate(getp(in, "data"), getp(in, "spec"));
  });

  // ===== select =====
  run("select", "basic", true, [](const Value& in) {
    auto out = std::make_shared<List>();
    for (const auto& v : select(getp(in, "obj"), getp(in, "query")))
      out->push_back(v);
    return Value(out);
  });
  run("select", "operators", true, [](const Value& in) {
    auto out = std::make_shared<List>();
    for (const auto& v : select(getp(in, "obj"), getp(in, "query")))
      out->push_back(v);
    return Value(out);
  });
  run("select", "edge", true, [](const Value& in) {
    auto out = std::make_shared<List>();
    for (const auto& v : select(getp(in, "obj"), getp(in, "query")))
      out->push_back(v);
    return Value(out);
  });
  run("select", "alts", true, [](const Value& in) {
    auto out = std::make_shared<List>();
    for (const auto& v : select(getp(in, "obj"), getp(in, "query")))
      out->push_back(v);
    return Value(out);
  });

  // ===== regex (parity floor: Go stdlib regexp; REGEX_API.md) =====
  auto rxs = [](const Value& v) { return v.is_string() ? v.as_string() : std::string(); };
  run("regex", "test", true, [&](const Value& in) {
    return Value(re_test(rxs(getp(in, "pattern")), rxs(getp(in, "input"))));
  });
  run("regex", "find", true, [&](const Value& in) {
    auto m = re_find(rxs(getp(in, "pattern")), rxs(getp(in, "input")));
    if (m.empty())
      return Value(nullptr);
    auto out = std::make_shared<List>();
    for (const auto& g : m)
      out->push_back(Value(g));
    return Value(out);
  });
  run("regex", "find_all", true, [&](const Value& in) {
    auto out = std::make_shared<List>();
    for (const auto& m : re_find_all(rxs(getp(in, "pattern")), rxs(getp(in, "input")))) {
      auto row = std::make_shared<List>();
      for (const auto& g : m)
        row->push_back(Value(g));
      out->push_back(Value(row));
    }
    return Value(out);
  });
  run("regex", "replace", true, [&](const Value& in) {
    return Value(
        re_replace(rxs(getp(in, "pattern")), rxs(getp(in, "input")), rxs(getp(in, "replacement"))));
  });
  run("regex", "escape", true,
      [&](const Value& in) { return Value(re_escape(rxs(getp(in, "val")))); });

  // `null: false` keeps a JSON null an ACTUAL null rather than the marker, so
  // select sees a present-but-null field.
  run("select", "nullkey", false, [](const Value& in) {
    auto out = std::make_shared<List>();
    for (const auto& v : select(getp(in, "obj"), getp(in, "query")))
      out->push_back(v);
    return Value(out);
  });

  // ===== sentinels: null and absent unified on observation =====
  run("sentinels", "getprop_unify", false,
      [](const Value& in) { return getprop(getp(in, "val"), getp(in, "key"), getp(in, "alt")); });
  run("sentinels", "getelem_absent", false,
      [](const Value& in) { return getelem(getp(in, "val"), getp(in, "key"), getp(in, "alt")); });
  run("sentinels", "haskey_unify", false,
      [](const Value& in) { return Value(haskey(getp(in, "val"), getp(in, "key"))); });
  run("sentinels", "isempty_unify", false, [](const Value& in) { return Value(isempty(in)); });
  run("sentinels", "isnode_unify", false, [](const Value& in) { return Value(isnode(in)); });
  run("sentinels", "stringify_null", false, [](const Value& in) { return Value(stringify(in)); });

  // condense / expand / iscondensed exist only in canonical TypeScript so far
  // - no port implements them, and check_parity.py already lists them as
  // pending. Named here so the gap is a visible TODO rather than three groups
  // nobody notices are missing.
  std::printf("  skip condense.condense, condense.expand, condense.iscondensed (not ported)\n");

  std::printf("=========================\n%d groups, %d failed\n\n", GROUPS, FAILED);

  return 0 == FAILED ? 0 : 1;
}
