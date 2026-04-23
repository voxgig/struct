// Walk benchmark — measures ns/node for the pool-based walk optimization.
// Gated on the WALK_BENCH=1 environment variable so `make bench` is cheap
// to skip if the user just wants to verify the binary builds.

#include <iostream>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <string>
#include <functional>

#include <nlohmann/json.hpp>

#include <voxgig_struct.hpp>

using namespace VoxgigStruct;

inline void Utility::set_key(const std::string& key, function_pointer p) {
  // Unused in bench; provided because utility_decls.hpp declares but does not define.
  (void)key; (void)p;
}
inline function_pointer& Utility::get_key(const std::string& key) {
  static function_pointer p = nullptr;
  (void)key;
  return p;
}
inline function_pointer& Utility::operator[](const std::string& key) { return get_key(key); }
inline void Utility::set_table(hash_table<std::string, function_pointer>&&) {}
Provider::Provider(const json&) {}
Provider Provider::test(const json&) { return Provider(nullptr); }
Provider Provider::test(void) { return Provider(nullptr); }
hash_table<std::string, Utility> Provider::utility() { return {}; }

// Build a complete tree with branching factor `w` and depth `d`.
// Every non-leaf has `w` children; every leaf is a string.
// Returns (json, total_node_count).
static json build_tree(int w, int d, size_t& node_count) {
  node_count++;
  if (d <= 0) {
    return std::string("leaf");
  }
  json obj = json::object();
  for (int i = 0; i < w; i++) {
    std::string k = "k" + std::to_string(i);
    obj[k] = build_tree(w, d - 1, node_count);
  }
  return obj;
}

// No-op apply: visits every node, records path length to prevent DCE.
struct Counter {
  size_t visits = 0;
  size_t path_len_sum = 0;
};

static void bench_scenario(const char* name, int w, int d, int iterations) {
  size_t node_count = 0;
  json tree = build_tree(w, d, node_count);

  Counter counter;
  JsonFunction apply_fn = [&counter](args_container&& args) -> json {
    counter.visits++;
    if (args.size() >= 4 && args[3].is_array()) {
      counter.path_len_sum += args[3].size();
    }
    return args.size() >= 2 ? std::move(args[1]) : json(nullptr);
  };

  // Warmup.
  {
    json tree_copy = tree;
    walk({ std::move(tree_copy), reinterpret_cast<intptr_t>(&apply_fn) });
  }
  counter = Counter{};

  auto t0 = std::chrono::steady_clock::now();
  for (int i = 0; i < iterations; i++) {
    json tree_copy = tree;
    walk({ std::move(tree_copy), reinterpret_cast<intptr_t>(&apply_fn) });
  }
  auto t1 = std::chrono::steady_clock::now();

  auto total_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count();
  double per_iter_ns = (double)total_ns / iterations;
  double per_node_ns = per_iter_ns / (double)node_count;

  std::cout << "[" << name << "] w=" << w << " d=" << d
            << " nodes=" << node_count
            << " iters=" << iterations
            << " total_ms=" << (total_ns / 1e6)
            << " per_iter_us=" << (per_iter_ns / 1e3)
            << " per_node_ns=" << per_node_ns
            << " visits=" << counter.visits
            << " path_sum=" << counter.path_len_sum
            << std::endl;
}

int main() {
  const char* flag = std::getenv("WALK_BENCH");
  if (!flag || std::strcmp(flag, "1") != 0) {
    std::cout << "Walk benchmark skipped (set WALK_BENCH=1 to run)." << std::endl;
    return 0;
  }

  std::cout << "Walk benchmark — pool-based path reuse" << std::endl;
  // Scenario params: iterations chosen so total work ~ 1-2M node visits each.
  bench_scenario("wide+deep",  8,    6, 5);   // ~299593 nodes/iter
  bench_scenario("very-wide",  1000, 2, 5);   // ~1001001 nodes/iter
  bench_scenario("very-deep",  2,    20, 2);  // ~2097151 nodes/iter

  return 0;
}
