// Voxgig Struct corpus driver — C++ port.
// Mirrors java/src/test/StructCorpusTest.java.
//
// Loads build/test/test.json, drives every (category, name) pair, and prints
// a per-.jsonic-file scoreboard plus a totals line.

#include <cstdio>
#include <fstream>
#include <iostream>
#include <map>
#include <string>
#include <vector>

#include "value.hpp"
#include "value_io.hpp"
#include "voxgig_struct.hpp"
#include "runner.hpp"

using namespace voxgig::structlib;
using runner::Result;
using runner::Subject;
using runner::runset;
using runner::runsetflags;
using runner::get_spec;

namespace {

std::map<std::string, Result> SCOREBOARD;

const std::map<std::string, std::string>& category_to_file() {
  static const std::map<std::string, std::string> M = {
    {"minor",     "minor.jsonic"},
    {"walk",      "walk.jsonic"},
    {"merge",     "merge.jsonic"},
    {"getpath",   "getpath.jsonic"},
    {"inject",    "inject.jsonic"},
    {"transform", "transform.jsonic"},
    {"validate",  "validate.jsonic"},
    {"select",    "select.jsonic"},
  };
  return M;
}

void run(const std::string& cat, const std::string& name, bool null_flag,
         const Subject& s) {
  std::string full = cat + "." + name;
  Value spec = get_spec(cat, name);
  Result r = runsetflags(full, spec, null_flag, s);
  SCOREBOARD[full] = r;
}

inline Value getp(const Value& in, const std::string& k) {
  return getprop(in, Value(k));
}
inline Value getpDef(const Value& in, const std::string& k, const Value& def) {
  return haskey(in, Value(k)) ? getprop(in, Value(k)) : def;
}

}  // namespace

int main() {
  // ===== minor =====
  run("minor", "isnode",  true,  [](const Value& in) { return Value(isnode(in)); });
  run("minor", "ismap",   true,  [](const Value& in) { return Value(ismap(in)); });
  run("minor", "islist",  true,  [](const Value& in) { return Value(islist(in)); });
  run("minor", "iskey",   false, [](const Value& in) { return Value(iskey(in)); });
  run("minor", "strkey",  false, [](const Value& in) { return Value(strkey(in)); });
  run("minor", "isempty", false, [](const Value& in) { return Value(isempty(in)); });
  run("minor", "isfunc",  true,  [](const Value& in) { return Value(isfunc(in)); });
  run("minor", "getprop", true,  [](const Value& in) {
    Value alt = getpDef(in, "alt", Value::undef());
    return alt.is_undef()
        ? getprop(getp(in, "val"), getp(in, "key"))
        : getprop(getp(in, "val"), getp(in, "key"), alt);
  });
  run("minor", "getelem", true,  [](const Value& in) {
    Value alt = getpDef(in, "alt", Value::undef());
    return alt.is_undef()
        ? getelem(getp(in, "val"), getp(in, "key"))
        : getelem(getp(in, "val"), getp(in, "key"), alt);
  });
  run("minor", "clone",   false, [](const Value& in) { return clone(in); });
  run("minor", "items",   true,  [](const Value& in) { return items_v(in); });
  run("minor", "keysof",  true,  [](const Value& in) {
    auto out = std::make_shared<List>();
    for (const auto& k : keysof(in)) out->push_back(Value(k));
    return Value(out);
  });
  run("minor", "haskey",  true, [](const Value& in) {
    return Value(haskey(getp(in, "src"), getp(in, "key")));
  });
  run("minor", "setprop", true, [](const Value& in) {
    Value parent = getpDef(in, "parent", Value::undef());
    if (parent.is_undef()) parent = Value(nullptr);
    return setprop(parent, getp(in, "key"), getp(in, "val"));
  });
  run("minor", "delprop", true, [](const Value& in) {
    Value parent = getpDef(in, "parent", Value::undef());
    if (parent.is_undef()) parent = Value(nullptr);
    return delprop(parent, getp(in, "key"));
  });
  run("minor", "stringify", true, [](const Value& in) {
    Value val = getpDef(in, "val", Value::undef());
    Value max = getp(in, "max");
    int m = max.is_int() ? static_cast<int>(max.as_int()) : -1;
    return Value(stringify(val, m));
  });
  run("minor", "jsonify",  true, [](const Value& in) {
    Value val = getp(in, "val");
    Value flags = getp(in, "flags");
    return Value(jsonify(val, flags));
  });
  run("minor", "pathify",  true, [](const Value& in) {
    Value path = getpDef(in, "path", Value::undef());
    Value from = getp(in, "from");
    Value to = getp(in, "to");
    int f = from.is_int() ? static_cast<int>(from.as_int()) : 0;
    int t = to.is_int()   ? static_cast<int>(to.as_int())   : 0;
    return Value(pathify(path, f, t));
  });
  run("minor", "escre",   true, [](const Value& in) { return Value(escre(in)); });
  run("minor", "escurl",  true, [](const Value& in) { return Value(escurl(in)); });
  run("minor", "join",    true, [](const Value& in) {
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
  run("minor", "filter",  true, [](const Value& in) {
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
    if (in.is_int()) return Value(typename_str(static_cast<int>(in.as_int())));
    return Value(typename_str(in));
  });
  run("minor", "typify",   true, [](const Value& in) {
    return Value(static_cast<int64_t>(typify(in)));
  });
  run("minor", "size",     true, [](const Value& in) -> Value {
    return Value(voxgig::structlib::size(in));
  });
  run("minor", "slice",    true, [](const Value& in) {
    Value val = getp(in, "val");
    Value start = getp(in, "start");
    Value end = getp(in, "end");
    return slice(val, start, end);
  });
  run("minor", "pad",      true, [](const Value& in) {
    Value val = getp(in, "val");
    Value p = getp(in, "pad");
    Value c = getp(in, "char");
    return Value(pad(val, p, c));
  });
  run("minor", "setpath",  false, [](const Value& in) {
    Value store = getp(in, "store");
    Value path = getp(in, "path");
    Value val = getp(in, "val");
    return setpath_v(store, path, val);
  });

  // ===== walk =====
  run("walk", "basic", true, [](const Value& in) {
    return walk_v(in,
        [](const Value& key, const Value& val, const Value&,
           const std::vector<std::string>& path) -> Value {
          if (val.is_string()) {
            std::string out = val.as_string() + "~";
            for (size_t i = 0; i < path.size(); i++) {
              if (i > 0) out += ".";
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
          top = child; cur = child;
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
        cur[0] = val.is_map()  ? Value(std::shared_ptr<Map>(new Map()))
               : val.is_list() ? Value(std::make_shared<List>())
               : val;
        return val;
      }
      Value v = val;
      size_t i = path.size();
      if (isnode(v)) {
        v = v.is_map() ? Value(std::shared_ptr<Map>(new Map()))
                       : Value(std::make_shared<List>());
        cur[i] = v;
      }
      setprop(cur[i - 1], key, v);
      return val;
    };
    walk_v(in, do_walk);
    return cur[0];
  });

  // ===== merge =====
  run("merge", "cases",     true, [](const Value& in) { return merge_v(in); });
  run("merge", "array",     true, [](const Value& in) { return merge_v(in); });
  run("merge", "integrity", true, [](const Value& in) { return merge_v(in); });
  run("merge", "depth",     true, [](const Value& in) {
    Value val = getp(in, "val");
    Value depth = getp(in, "depth");
    int d = depth.is_int() ? static_cast<int>(depth.as_int()) : MAXDEPTH;
    return merge_v(val, d);
  });

  // ===== getpath =====
  run("getpath", "basic", true, [](const Value& in) {
    return getpath_v(getp(in, "store"), getp(in, "path"));
  });
  run("getpath", "relative", true, [](const Value& in) {
    Injection inj(Value::undef(), Value::undef());
    if (haskey(in, Value("dparent"))) inj.dparent = getp(in, "dparent");
    if (haskey(in, Value("dpath"))) {
      Value dp = getp(in, "dpath");
      inj.dpath.clear();
      if (dp.is_list()) {
        for (const auto& p : *dp.as_list()) inj.dpath.push_back(strkey(p));
      } else if (dp.is_string()) {
        // Split on '.'.
        const std::string& s = dp.as_string();
        size_t pos = 0;
        while (pos <= s.size()) {
          size_t dot = s.find('.', pos);
          if (dot == std::string::npos) { inj.dpath.push_back(s.substr(pos)); break; }
          inj.dpath.push_back(s.substr(pos, dot - pos));
          pos = dot + 1;
        }
      }
    }
    if (haskey(in, Value("base"))) {
      Value b = getp(in, "base");
      if (b.is_string()) inj.base = b.as_string();
    }
    bool any = haskey(in, Value("dparent")) || haskey(in, Value("dpath")) || haskey(in, Value("base"));
    return getpath_v(getp(in, "store"), getp(in, "path"), any ? &inj : nullptr);
  });
  run("getpath", "special", true, [](const Value& in) {
    Value injv = getp(in, "inj");
    if (!injv.is_map()) return getpath_v(getp(in, "store"), getp(in, "path"));
    Injection inj(Value::undef(), Value::undef());
    Value k = getp(injv, "key");
    if (k.is_string()) inj.key = k.as_string();
    Value m = getp(injv, "meta");
    if (m.is_map()) inj.meta = m.as_map();
    Value dp = getp(injv, "dparent");
    if (!dp.is_undef()) inj.dparent = dp;
    Value dpa = getp(injv, "dpath");
    if (dpa.is_list()) {
      inj.dpath.clear();
      for (const auto& p : *dpa.as_list()) inj.dpath.push_back(strkey(p));
    }
    return getpath_v(getp(in, "store"), getp(in, "path"), &inj);
  });

  // ===== inject =====
  run("inject", "string", true, [](const Value& in) {
    return inject(getp(in, "val"), getp(in, "store"));
  });
  run("inject", "deep", true, [](const Value& in) {
    return inject(getp(in, "val"), getp(in, "store"));
  });

  // ===== transform =====
  run("transform", "paths", true, [](const Value& in) {
    return transform(getp(in, "data"), getp(in, "spec"));
  });
  run("transform", "cmds", true, [](const Value& in) {
    return transform(getp(in, "data"), getp(in, "spec"));
  });
  run("transform", "each", true, [](const Value& in) {
    return transform(getp(in, "data"), getp(in, "spec"));
  });
  run("transform", "pack", true, [](const Value& in) {
    return transform(getp(in, "data"), getp(in, "spec"));
  });
  run("transform", "modify", true, [](const Value& in) {
    auto opts = std::shared_ptr<Map>(new Map());
    Modify mod = [](const Value& val, const Value& key, const Value& parent,
                    Injection& inj, const Value& store) {
      if (!key.is_undef() && parent.is_map() && val.is_string()) {
        parent.as_map()->set(strkey(key), Value("@" + val.as_string()));
      }
    };
    opts->set("modify", Value(mod));
    return transform(getp(in, "data"), getp(in, "spec"), Value(opts));
  });
  run("transform", "ref", true, [](const Value& in) {
    return transform(getp(in, "data"), getp(in, "spec"));
  });
  run("transform", "format", false, [](const Value& in) {
    return transform(getp(in, "data"), getp(in, "spec"));
  });
  run("transform", "apply", true, [](const Value& in) {
    auto opts = std::shared_ptr<Map>(new Map());
    auto extra = std::shared_ptr<Map>(new Map());
    Injector apply_fn = [](Injection&, const Value& val, const std::string&, const Value&) -> Value {
      if (val.is_string()) {
        std::string s = val.as_string();
        for (auto& c : s) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        return Value(s);
      }
      return val;
    };
    extra->set("apply", Value(apply_fn));
    opts->set("extra", Value(extra));
    return transform(getp(in, "data"), getp(in, "spec"), Value(opts));
  });

  // ===== validate =====
  run("validate", "basic",   true, [](const Value& in) { return validate(getp(in, "data"), getp(in, "spec")); });
  run("validate", "child",   true, [](const Value& in) { return validate(getp(in, "data"), getp(in, "spec")); });
  run("validate", "one",     true, [](const Value& in) { return validate(getp(in, "data"), getp(in, "spec")); });
  run("validate", "exact",   true, [](const Value& in) { return validate(getp(in, "data"), getp(in, "spec")); });
  run("validate", "invalid", true, [](const Value& in) { return validate(getp(in, "data"), getp(in, "spec")); });
  run("validate", "special", true, [](const Value& in) {
    Value inj_v = getp(in, "inj");
    return inj_v.is_map() ? validate(getp(in, "data"), getp(in, "spec"), inj_v)
                          : validate(getp(in, "data"), getp(in, "spec"));
  });

  // ===== select =====
  run("select", "basic",     true, [](const Value& in) {
    auto out = std::make_shared<List>();
    for (const auto& v : select(getp(in, "obj"), getp(in, "query"))) out->push_back(v);
    return Value(out);
  });
  run("select", "operators", true, [](const Value& in) {
    auto out = std::make_shared<List>();
    for (const auto& v : select(getp(in, "obj"), getp(in, "query"))) out->push_back(v);
    return Value(out);
  });
  run("select", "edge",      true, [](const Value& in) {
    auto out = std::make_shared<List>();
    for (const auto& v : select(getp(in, "obj"), getp(in, "query"))) out->push_back(v);
    return Value(out);
  });
  run("select", "alts",      true, [](const Value& in) {
    auto out = std::make_shared<List>();
    for (const auto& v : select(getp(in, "obj"), getp(in, "query"))) out->push_back(v);
    return Value(out);
  });

  // Aggregate per-file scoreboard.
  std::map<std::string, std::pair<int, int>> by_file;
  std::map<std::string, std::vector<std::pair<std::string, std::string>>> details;
  int totalP = 0, totalT = 0;
  for (const auto& [key, r] : SCOREBOARD) {
    std::string cat = key.substr(0, key.find('.'));
    auto it = category_to_file().find(cat);
    std::string file = it == category_to_file().end() ? cat + ".jsonic" : it->second;
    by_file[file].first  += r.passed;
    by_file[file].second += r.total;
    details[file].push_back({key, std::to_string(r.passed) + "/" + std::to_string(r.total)});
    totalP += r.passed;
    totalT += r.total;
  }

  std::cout << "\n========= STRUCT CORPUS SCOREBOARD =========\n";
  for (const auto& [file, pt] : by_file) {
    std::printf("  %-18s %4d / %4d\n", file.c_str(), pt.first, pt.second);
    for (const auto& [name, tally] : details[file]) {
      std::printf("      %-30s %s\n", name.c_str(), tally.c_str());
    }
  }
  std::printf("  %-18s %4d / %4d\n", "TOTAL", totalP, totalT);
  std::cout << "============================================\n";

  // Optionally print failure details when CORPUS_VERBOSE is set.
  if (const char* v = std::getenv("CORPUS_VERBOSE"); v && std::string(v) != "0") {
    for (const auto& [name, r] : SCOREBOARD) {
      if (r.failures.empty()) continue;
      std::cerr << "\n--- " << name << " (" << r.passed << "/" << r.total << ") ---\n";
      int shown = 0;
      for (const auto& f : r.failures) {
        std::cerr << "  " << f << "\n";
        if (++shown >= 5) { std::cerr << "  ... " << (r.failures.size() - shown) << " more\n"; break; }
      }
    }
  }

  // Write target/corpus-scoreboard.json
  std::ofstream out("corpus-scoreboard.json");
  if (out) {
    out << "{\n  \"files\": {\n";
    bool first = true;
    for (const auto& [file, pt] : by_file) {
      if (!first) out << ",\n";
      first = false;
      out << "    \"" << file << "\": {\"passed\": " << pt.first
          << ", \"total\": " << pt.second << "}";
    }
    out << "\n  },\n  \"total\": {\"passed\": " << totalP
        << ", \"total\": " << totalT << "}\n}\n";
  }

  return 0;
}
