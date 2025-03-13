#include <iostream>
#include <fstream>

#include <nlohmann/json.hpp>

#include <voxgig_struct.hpp>
#include <runner.hpp>


#define TEST_CASE(TEST_NAME) std::cout << "Running: " << TEST_NAME << " at " << __LINE__ << std::endl;

#define TEST_SUITE(NAME) std::cout << NAME << " " << " at " << __LINE__ << std::endl;


using namespace VoxgigStruct;

inline void Utility::set_key(const std::string& key, function_pointer p) {
  table[key] = p;
}

inline function_pointer& Utility::get_key(const std::string& key) {
  return table[key];
}

inline function_pointer& Utility::operator[](const std::string& key) {
  return get_key(key);
}

inline void Utility::set_table(hash_table<std::string, function_pointer>&& new_table) {
  table = std::move(new_table);
}

struct Struct : public Utility {

  Struct() {
    set_table({
        { "isnode", isnode },
        { "ismap",  ismap  },
        { "islist", islist },
        { "iskey", iskey },
        { "isempty", isempty },
        { "isfunc", isfunc<args_container&&> },
        { "getprop", getprop },
        { "keysof", keysof },
        { "haskey", haskey },
        { "items", items },
        { "escre", escre },
        { "joinurl", joinurl },
        { "stringify", stringify },
        { "clone", clone },
        { "setprop", setprop },

        { "walk", walk },
        { "merge", merge },

    });

  }

  ~Struct() = default;

};


// NOTE: More dynamic approach compared to function overloading
Provider::Provider(const json& opts = nullptr) {
  // Do opts
}

Provider Provider::test(const json& opts) {
  return Provider(opts);
}

Provider Provider::test(void) {
  return Provider(nullptr);
}


hash_table<std::string, Utility> Provider::utility() {
  return { 
    {
      "struct", Struct()
    }
  };

}

json walkpath(args_container&& args) {
  json _key = args.size() == 0 ? nullptr : std::move(args[0]);
  json val = args.size() < 2 ? nullptr : std::move(args[1]);
  json _parent = args.size() < 3 ? nullptr : std::move(args[2]);
  json path = args.size() < 4 ? nullptr : std::move(args[3]);

  if(val.is_string()) {
    std::string out = val.get<std::string>() + "~";

    std::string path_joint;

    int i = 0;
    int size = path.size();

    // std::cout << "path::: " << path << std::endl;

    for(json::iterator p = path.begin(); p != path.end(); p++, i++) {
      path_joint += p->get<std::string>();

      if(i < size-1) {
        path_joint += '.';
      }
    }

    out += path_joint;

    // std::cout << "out:: " << out << std::endl;



    return out;
  }

  return val;

};

int main() {

  Provider provider = Provider::test();

  RunnerResult runparts = runner("struct", {}, "../build/test/test.json", provider);

  json spec = std::move(runparts.spec);
  auto runset = runparts.runset;


  TEST_SUITE("TEST_STRUCT") {

    TEST_CASE("test_minor_isnode") {
      runset(spec["minor"]["isnode"], isnode, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_ismap") {
      runset(spec["minor"]["ismap"], ismap, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_islist") {
      runset(spec["minor"]["islist"], islist, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_iskey") {
      runset(spec["minor"]["iskey"], iskey, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_isempty") {
      runset(spec["minor"]["isempty"], isempty, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_isfunc") {
      // resolve by (function_pointer)
      runset(spec["minor"]["isfunc"],
          static_cast<function_pointer>(isfunc<args_container&&>),
          { { "fixjson", false } }
          );
    }

    TEST_CASE("test_minor_getprop") {
      JsonFunction getprop_wrapper = [](args_container&& args) -> json {
        json& vin = args[0];
        // std::cout << "json vin: " << vin << std::endl;
        // NOTE: operator[] is not good (isn't the best lookup) for auxiliary space since it creates an empty entry if the value is not found
        if(!vin.contains("alt")) {
          return getprop({
              vin.value("val", json(nullptr)),
              vin.value("key", json(nullptr))
              });
        } else {
          return getprop({
              vin.value("val", json(nullptr)), 
              vin.value("key", json(nullptr)),
              vin.value("alt", json(nullptr))
              });
        }
      };

      // TODO: Use nullptr for now since we can't have std::function with optional arguments. Instead, we need to rewrite the entire class to implement our own closure and "operator()"
      runset(spec["minor"]["getprop"], getprop_wrapper, nullptr);
    }

    TEST_CASE("test_minor_keysof") {
      runset(spec["minor"]["keysof"], keysof, nullptr);
    }

    TEST_CASE("test_minor_haskey") {
      runset(spec["minor"]["haskey"], haskey, nullptr);
    }

    TEST_CASE("test_minor_items") {
      runset(spec["minor"]["items"], items, nullptr);
    }

    TEST_CASE("test_minor_escre") {
      runset(spec["minor"]["escre"], escre, nullptr);
    }

    TEST_CASE("test_minor_escurl") {
      runset(spec["minor"]["escurl"], escurl, nullptr);
    }

    TEST_CASE("test_minor_joinurl") {
      runset(spec["minor"]["joinurl"], joinurl, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_stringify") {
      JsonFunction stringify_wrapper = [](args_container&& args) -> json {
        json& vin = args[0];
        // std::cout << "json vin: " << vin << std::endl;
        // NOTE: operator[] is not good (isn't the best lookup) for auxiliary space since it creates an empty entry if the value is not found
        if(!vin.contains("max")) {
          // NOTE: edge case "{ in: { }, out: '' }"
          if(vin.contains("val")) {
            return stringify({
                vin.value("val", json(nullptr))
               });
          } else {
            return stringify({});
          }
        } else {
          return stringify({
              vin.value("val", json(nullptr)),
              vin.value("max", json(nullptr))
              });
        }
      };

      // TODO: Use nullptr for now since we can't have std::function with optional arguments. Instead, we need to rewrite the entire class to implement our own closure and "operator()"
      runset(spec["minor"]["stringify"], stringify_wrapper, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_clone") {
      runset(spec["minor"]["clone"], static_cast<function_pointer>(clone), nullptr);
    }

    TEST_CASE("test_minor_setprop") {
      JsonFunction setprop_wrapper = [](args_container&& args) -> json {
        json& vin = args[0];
        return setprop({
            vin.value("parent", json(nullptr)),
            vin.value("key", json(nullptr)),
            vin.value("val", json(nullptr))
            });
      };

      // TODO: Use nullptr for now since we can't have std::function with optional arguments. Instead, we need to rewrite the entire class to implement our own closure and "operator()"
      runset(spec["minor"]["setprop"], setprop_wrapper, nullptr);
    }

    // -------------------------------------------------
    // walk tests
    // -------------------------------------------------

    TEST_CASE("test_walk_basic") {
      JsonFunction* _walkpath = new JsonFunction(walkpath);

      JsonFunction walk_wrapper = [=](args_container&& args) -> json {
        json vin = args.size() == 0 ? nullptr : std::move(args[0]);
        return walk({
            std::move(vin),
            reinterpret_cast<intptr_t>(_walkpath),
            });
      };

      // TODO: Use nullptr for now since we can't have std::function with optional arguments. Instead, we need to rewrite the entire class to implement our own closure and "operator()"
      runset(spec["walk"]["basic"], walk_wrapper, nullptr);

      delete _walkpath;
    }

    // -------------------------------------------------
    // merge tests
    // -------------------------------------------------
    
    TEST_CASE("test_merge_basic") {

      json test_data = clone({ spec["merge"]["basic"] });
      // std::cout << test_data << std::endl;

      assert(merge({ test_data["in"] }) == test_data["out"]);
    }



  }

  return 0;
}
