#include "utility_decls.hpp"

// Struct Utility Functions


namespace VoxgigStruct {

  namespace S {
    const std::string empty = "";
  };

  inline json isnode(args_container&& args) {
    json val = args.size() == 0 ? nullptr : std::move(args[0]);

    return static_cast<bool>(val.is_array() || val.is_object());
  }

  inline json ismap(args_container&& args) {
    json val = args.size() == 0 ? nullptr : std::move(args[0]);

    // NOTE: explicit static_case not needed but let's stay explicit in case we change the library
    return static_cast<bool>(val.is_object());
  }

  inline json islist(args_container&& args) {
    json val = args.size() == 0 ? nullptr : std::move(args[0]);

    return static_cast<bool>(val.is_array());
  }


  json iskey(args_container&& args) {
    json val = args.size() == 0 ? nullptr : std::move(args[0]);

    // TODO: Refactor the if statements
    if(val.is_string()) {
      return (val.get<std::string>()).length() > 0;
    }

    if(val.is_boolean()) {
      return false;
    }

    if(val.is_number_integer()) {
      return true;
    }


    return false;
  }

  json isempty(args_container&& args) {
    json val = args.size() == 0 ? nullptr : std::move(args[0]);

    // val.is_null()
    if(val == nullptr) {
      return true;
    }

    if(val == S::empty) {
      return true;
    }

    if(islist({ val }) && val.size() == 0) {
      return true;
    }

    if(ismap({ val }) && val.size() == 0) {
      return true;
    }



    return false;
  }

  // NOTE: Use template specialization
  // TODO: For Python and JS, this is determined at runtime (via callable or similar) so that doesn't mirror the exact implementation as it is supposed to
  // Proposal: Create a wrapper:
  // class {
  //   type t;
  //   union {
  //      json json_obj;
  //      std::function<json(args_container&&)> func;
  //   }
  // };
  // Alternatively, our own Data Structure
  // class VxgDataStruct { };

  template<class T>
    json isfunc(T&& args) {
      return false;
    }

  template<class T>
    json isfunc(T& args) {
      return false;
    }

  template<>
    json isfunc<args_container&&>(args_container&& args) {
      return false;
    }

  template<>
    json isfunc<std::function<json(args_container&&)>>(std::function<json(args_container&&)>& func) {
      return true;
    }

  template<>
    json isfunc<std::function<json(args_container&&)>>(std::function<json(args_container&&)>&& func) {
      return true;
    }


  json getprop(args_container&& args) {
    json val = args.size() == 0 ? nullptr : std::move(args[0]);
    json key = args.size() < 2 ? nullptr : std::move(args[1]);
    json alt = args.size() < 3 ? nullptr : std::move(args[2]);

    if(val.is_null()) {
      return alt;
    }

    if(key.is_null()) {
      return alt;
    }

    json out = alt;

    if(ismap({val})) {
      out = val.value(key.is_string() ? key : json(key.dump()), alt);
    }
    else if(islist({val})) {
      int _key {0};

      try {
        _key = key.get<int>();
      } catch(const json::exception&) {

        try {
          std::string __key = key.get<std::string>();
          // TODO: Refactor: this is O(2n)
          Auxiliary::validate_int(__key);
          _key = std::stoi(__key);
          goto try_access;

        } catch(...) {}

        return alt;
      }

try_access:
      if(0 <= _key && _key < val.size()) {
        return val[_key];
      } else {
        return alt;
      }

    }

    if(out.is_null()) {
      out = alt;
    }



    return out;
  }


  json keysof(args_container&& args) {
    json val = args.size() == 0 ? nullptr : args[0];

    if(isnode({val}) == false) {
      return json::array();
    } else if(ismap({val})) {
      json keys = json::array();
      for(json::iterator it = val.begin(); it != val.end(); it++) {
        keys.push_back(it.key());
      }
      return keys; // TODO: sorted(val.keys()). HOWEVER, the keys appear to be sorted (in order) by default. Try "std::cout << json::parse(R"({"b": 1, "a": 2})") << std::endl;"
    } else {
      json arr = json::array();
      for(int i = 0; i < val.size(); i++) {
        arr.push_back(std::to_string(i));
      }
      return arr;
    }

  }

  json haskey(args_container&& args) {
    json val = args.size() == 0 ? nullptr : std::move(args[0]);
    json key = args.size() < 2 ? nullptr : std::move(args[1]);

    return getprop({val, key}) != nullptr;
  }

  json items(args_container&& args) {
    json val = args.size() == 0 ? nullptr : std::move(args[0]);

    if(ismap({ val })) {
      json _items = json::array();
      for(json::iterator it = val.begin(); it != val.end(); it++) {
        json pair = json::array();
        pair.push_back(it.key());
        pair.push_back(it.value());

        _items.push_back(pair);
      }
      return _items;

    } else if(islist({ val })) {
      json _items = json::array();
      int i = 0;

      for(json::iterator it = val.begin(); it != val.end(); it++, i++) {
        json pair = json::array();
        pair.push_back(i);
        pair.push_back(it.value());
        _items.push_back(pair);
      }

      return _items;
    } else {
      return json::array();
    }

  }

  json escre(args_container&& args) {
    json s = args.size() == 0 ? nullptr : std::move(args[0]);

    if(s == nullptr) {
      s = S::empty;
    }

    const std::string& s_string = s.get<std::string>();

    const std::regex pattern(R"([.*+?^${}()|[\]\\])");

    return std::regex_replace(s_string, pattern, R"(\$&)");

  }

  json escurl(args_container&& args) {
    json s = args.size() == 0 ? nullptr : std::move(args[0]);

    if(s == nullptr) {
      s = S::empty;
    }

    const std::string& s_string = s.get<std::string>();

    std::ostringstream escaped;
    escaped.fill('0');
    escaped << std::hex;

    for (unsigned char c : s_string) {
      // Encode non-alphanumeric characters except '-' '_' '.' '~'
      if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
        escaped << c;
      } else {
        escaped << '%' << std::uppercase << std::setw(2) << int(c);
        escaped << std::nouppercase;
      }
    }

    return escaped.str();
  }

  json joinurl(args_container&& args) {
    json _sarr = args.size() == 0 ? nullptr : std::move(args[0]);

    std::vector<std::string> sarr;

    std::vector<std::string> parts;

    for(json::iterator it = _sarr.begin(); it != _sarr.end(); it++) {
      json v = it.value();
      if(v != nullptr && v != "") {
        sarr.push_back(v.get<std::string>());
      }
    }


    // Refactor: double loop
    for (size_t i = 0; i < sarr.size(); ++i) {
      std::string s = sarr[i];

      if(i == 0) {
            s = std::regex_replace(s, std::regex(R"(([^/])/+)"), "$1/");
            s = std::regex_replace(s, std::regex(R"(/+$)"), "");
      } else {
            s = std::regex_replace(s, std::regex(R"(([^/])/+)"), "$1/"); // Merge multiple slashes after a character
            s = std::regex_replace(s, std::regex(R"(^/+)"), ""); // Remove leading slashes
            s = std::regex_replace(s, std::regex(R"(/+$)"), "");
      }

      if (!s.empty()) {
        parts.push_back(s);
      }

    }

    std::string out = parts.empty() ? "" : std::accumulate(parts.begin() + 1, parts.end(), parts[0],
        [](const std::string& a, const std::string& b) {
          return a + "/" + b;
        });

    return out;

  }

  json stringify(args_container&& args) {
    json val = args.size() == 0 ? nullptr : std::move(args[0]);
    json maxlen = args.size() < 2 ? nullptr : std::move(args[1]);

    json _json = S::empty;

    if(args.size() == 0){
      return S::empty;
    }

    try {
      _json = val.dump();
    } catch(const json::exception&) {
      _json = val; // TODO: Possibly an edge case
    }

    std::string _jsonstr = std::regex_replace(_json.get<std::string>(), std::regex("(\")"), "");

    if(maxlen != nullptr) {
      int _maxlen = maxlen.get<int>();

      std::string js = _jsonstr.substr(0, _maxlen);

      _jsonstr = _maxlen < _jsonstr.length() ? (js.substr(0, _maxlen-3)) + "..." : _jsonstr;
    }

    return _jsonstr;
  }
  
  json clone(args_container&& args) {
    json val = args.size() == 0 ? nullptr : std::move(args[0]);

    if(val.is_null()) {
      return nullptr;
    }

    /* NOTE: Simple clone without replace/reviver as this use case is impractical in C++ unless we do it in as part of our own interface */

    /*
    if(val.is_array()) {
      json arr = json::array();

      for(json::iterator item = val.begin(); item != val.end(); item++) {
        arr.push_back(
            clone({item.value()})
        );
      }

      return arr;

    } else if(val.is_object()) {
      json obj = json::object();

      for(json::iterator item = val.begin(); item != val.end(); item++) {
        obj[item.key()] = clone({ item.value() });
      }

      return obj;
    }
    */
    
    return val;
  }

  json setprop(args_container&& args) {
    json parent = args.size() == 0 ? nullptr : std::move(args[0]);
    json key = args.size() < 2 ? nullptr : std::move(args[1]);
    json val = args.size() < 3 ? nullptr : std::move(args[2]);

    if(iskey({key}) == false) {
      return parent;
    }

    if(ismap({parent})) {
      std::string _key;
      try {
        _key = key.get<std::string>();
      } catch(const json::exception&) {
        _key = key.dump();
      }

      if(val.is_null()) {
        parent.erase(_key);
      } else {
        // NOTE: [json.exception.type_error.305] cannot use operator[] with a numeric argument with object
        parent[_key] = val;
      }

    } else if(islist({parent})) {
      int key_i;
      try {
        key_i = key.get<int>();
      } catch(const json::exception&) {
        return parent;
      }

      if(val.is_null()) {
        if(0 <= key_i && key_i < parent.size()) {
          // Shift items left
          for(int pI = key_i; pI < parent.size() - 1; pI++) {
            parent[pI] = parent[pI + 1];
          }
          // STL - vector pointer
          // NOTE: parent.get<std::vector<json>>().pop_back(); // WON'T CUT IT. See the note below
          std::vector<json>* parent_arr = parent.get_ptr<std::vector<json>*>();
          parent_arr->pop_back();
          // Inefficient: parent.erase(parent.size() - 1);

        }
      } else {
        // Non-empty insert
        if(key_i >= 0) {
          if(key_i >= parent.size()) {
            parent.push_back(val);
          } else {
            parent[key_i] = val;
          }
        } else {
          /*
          // NOTE: This is bad due to the implicit copy operator
          std::vector<json> json_vector = parent.get<std::vector<json>>();
          json_vector.emplace(json_vector.begin(), val);
          // This won't cut it either
          std::vector<json> json_vector;
          parent.get_to(json_vector);

          json_vector.insert(json_vector.begin(), val);
          */

          std::vector<json>* parent_arr = parent.get_ptr<std::vector<json>*>();
          parent_arr->insert(parent_arr->begin(), val);

          // Alternatively: parent.insert(parent.begin(), val);
        }
      }


    }

    return parent;

  }

  json walk(args_container&& args) {
    // These arguments are the public interface.
    json val = args.size() == 0 ? nullptr : std::move(args[0]);
    json apply = args.size() < 2 ? nullptr : std::move(args[1]);

    // These arguments are used for recursive state.
    json key = args.size() < 3 ? nullptr : std::move(args[2]);
    json parent = args.size() < 4 ? nullptr : std::move(args[3]);
    json path = args.size() < 5 ? nullptr : std::move(args[4]);


    // NOTE: CHEAT SINCE WE CAN'T PASS A DATA STRUCTURE LIKE THIS INTO JSON SAFELY
    JsonFunction* _apply = reinterpret_cast<JsonFunction*>(apply.get<intptr_t>());

    /*
      Walk a data structure depth-first, calling apply at each node (after children).
    */

    if(path == nullptr) {
      path = json::array();
    }

    if(isnode({ val })) {
      json _items = items({ val });

      for(json::iterator item = _items.begin(); item != _items.end(); item++) {
        json value = item.value();
        json ckey = value[0];
        json child = value[1];

        json _path = json::array();
        for(json::iterator p = path.begin(); p != path.end(); p++) {
          _path.push_back(p.value());
        }

        /*
        std::cout << "_path:: " << _path << std::endl;
        std::cout << path << std::endl;
        std::cout << "ckey:: " << ckey << std::endl;
        std::cout << "child:: " << child << std::endl;
        */

        try {
          _path.push_back(ckey.get<std::string>());
        } catch(const json::exception&) {
          _path.push_back(ckey.dump());
        }

        // NOTE: MUST DO "val = setprop(...)" since val as an argument is deep-copied. In other words, reference counting is not supported.
        val = setprop({ val, ckey, walk({ child, apply, ckey, val, _path})});

      }

    }

    // Nodes are applied *after* their children.
    // For the root node, key and parent will be UNDEF.
    return _apply->operator()({ key, val, parent, path });
  }

  json merge(args_container&& args) {
    /*
      Merge a list of values into each other. Later values have
      precedence.  Nodes override scalars. Node kinds (list or map)
      override each other, and do *not* merge.  The first element is
      modified.
    */

    json objs = args.size() == 0 ? nullptr : std::move(args[0]);

    if(islist({objs}) == false) {
      return objs;
    }
    if(objs.size() == 0) {
      return nullptr;
    }
    if(objs.size() == 1) {
      return objs[0];
    }

    json out = json::object();

    for(int i = 0; i < objs.size(); i++) {
      out.merge_patch(objs[i]);
    }

    /*
    if(islist({objs}) == false) {
      return objs;
    }
    if(objs.size() == 0) {
      return nullptr;
    }
    if(objs.size() == 1) {
      return objs[0];
    }

    // Merge a list of values.
    json out = getprop({ objs, 0, json::object() });

    for(int i = 1; i < objs.size(); i++) {
      json& obj = objs[i];

      if(isnode({ obj }) == false) {
        out = obj;
      } else {

        // Nodes win, also over nodes of a different kind
        if(isnode({ out }) == false || 
            (ismap({ obj }).get<bool>() && islist({ obj }).get<bool>()) ||
            (islist({ obj }).get<bool>() && ismap({ out }).get<bool>())) {
          out = obj;
        } else {

          json cur = json::array({ out });
          int cI = 0;

          std::cout << "before cI: " << cI << std::endl;

          JsonFunction* merger = new JsonFunction([&cur, &cI](args_container&& args) -> json {
              
              json key = args.size() == 0 ? nullptr : std::move(args[0]);
              json val = args.size() < 2 ? nullptr : std::move(args[1]);
              
              json parent = args.size() < 3 ? nullptr : std::move(args[2]);
              json path = args.size() < 4 ? nullptr : std::move(args[3]);


              if(key == nullptr) {
                return val;
              }

              int lenpath = path.size();
              cI = lenpath - 1;

              for(int i = 0; i < 1+cI-cur.size(); i++) {
                cur.push_back(json(nullptr));
              }

              if(cur[cI] == nullptr) {
                // cur[cI] = get
              }

              if(isnode({val}).get<bool>() && !(isempty({ val }).get<bool>())) {

                for(int i = 0; i < 2+cI+cur.size(); i++) {
                  cur.push_back(json(nullptr));
                }

                cur[cI] = setprop({ cur[cI], key, cur[cI + 1] });

                cur[cI + 1] = json(nullptr);


              } else {
                // Scalar child.
                cur[cI] = setprop({ cur[cI], key, val });
              }

              return val;
          });

          walk({ obj, reinterpret_cast<intptr_t>(merger) });

          std::cout << "after cI: " << cI << std::endl;

          delete merger;


        }

      }

    }
  */



    return out;
  }


}
