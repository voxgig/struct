#include <iostream>
#include <sstream>
#include <vector>

#include <nlohmann/json.hpp>


using json = nlohmann::json;

using JsonFunction = std::function<json(std::vector<json>)>;
using function_pointer = json(*)(std::vector<json>);

// g++ library_overview.cpp --std=c++11 -o out.out -I ~/Project/json/include && ./out.out


struct address
{
  std::string m_val;
  address(std::string rhs = "") : m_val(std::move(rhs)) {}
};

struct function_wrapper
{
  JsonFunction function;

  function_wrapper(JsonFunction function) {
    this->function = function;
  }

  std::string to_string() const {
    std::stringstream ss;

    // std::cout << (void*)(this->function).target() << std::endl;
    // ss << typeid(function).name();
    ss << &function;

    return ss.str();

  }

};

static void to_json(nlohmann::json& j, const address& a)
{
  j = a.m_val;
}

static void to_json(nlohmann::json& j, const function_wrapper& function)
{
  // j = std::stoi(function.to_string());
  j = reinterpret_cast<uintptr_t>(&function.function);
  // std::cout << "COUT: " << &(function.function) << std::endl;
}

/*
   template <typename BasicJsonType>
   static void from_json(BasicJsonType& j, const JsonFunction& function)
   {
   }
 */


json d(std::vector<json> args) {
  return 10101;
}

int main() {

  {
    // a JSON value
    json j_document = R"({
  "a": "b",
  "b": 1
})"_json;

    // a patch
    json j_patch = R"({
  "b": 2,
  "c": 3
})"_json;

    // apply the patch
    j_document.merge_patch(j_patch);

    std::cout << j_document << std::endl;

    }

{
  JsonFunction dd = d;
  function_wrapper f = dd;


  json obj = json(f);

  std::cout << obj << std::endl;
  std::cout << obj.get<uintptr_t>() << std::endl;

  JsonFunction* ptr_function = reinterpret_cast<JsonFunction*>(obj.get<uintptr_t>());

  // NOTE: VERY UNSAFE BUT SHOULD BE OK FOR FUNCTIONS DECLARED AT C LEVEL
  std::cout << (*ptr_function)({}) << std::endl;

}

{
  json d = "AAA";

  json a = nullptr;

  json b = "";

  std::cout << (a == nullptr) << std::endl;
  std::cout << (b == "") << std::endl;

  if(d.is_string()) {
    std::string conv = d.get<std::string>();

    std::cout << conv << std::endl;
  }
}

// vector conversion
{
  json obj = json::parse("[1, 2, 3, \"A\"]");
  // This conversion takes the same amount of auxiliary space both for std::move and copy operations
  std::vector<json> obj1 = obj;

  std::cout << obj << std::endl;
  // std::cout << obj1 << std::endl;

}

{
  json obj = json::parse("{}");

  // non-existent key for this lookup creates an entry in the memory so contains or better, "find" is recommended.
  std::cout << obj["a"] << std::endl;
  std::cout << obj.contains("a") << std::endl; // True :)

}

{
  // Non-string key lookup test
  json a = json::parse("{\"1\": 2}");

  json key = "1"; // fails
  key = 1;
  // a[1] fails
  std::cout << a["1"] << std::endl;
  std::cout << a[key.dump()] << std::endl;


  json arr = json::parse("[ \"a\" ]");

  // TODO: Add a testcase for this
  key = "0a1"; // THIS WILL CAUSE PROBLEMS

  std::cout << arr[std::stoi(key.get<std::string>())] << std::endl;


  std::cout << json::parse(R"({"b": 1, "a": 2})") << std::endl;
  std::cout << json::parse(R"(["b", "a"])") << std::endl;

  /*
     key = "0";

     key.get<int>();
   */

}

{
  assert(json::parse(R"({"a": 1})") == json::parse(R"({"a": 1.0})"));
  assert(json::parse(R"({"a": 1})") != json::parse(R"({"a": 1.1})"));
  assert(json::parse(R"({"a": 1})") == json::parse(R"({"a": 1})"));

}

{
  json value = 1;

  value = value.dump();


  std::string c = value.get<std::string>();

  assert(c == "1");
}

/*
   {
// Provider check
Provider provider;
hash_table<std::string, Utility> utility = provider.utility();

Utility _struct = utility["struct"];

std::cout << "_struct key: " << _struct["isnode"]({ json::array() }) << std::endl;



}
 */

/*
// Equality Checks
{
// Shallow Equal
json obj1 = json::parse(R"({"a": 1, "b": 2})");
json obj2 = json::parse(R"({"a": 1, "b": 2})");

// Deep Equal
json obj3 = json::parse(R"({"a": {"b": 1}})");
json obj4 = json::parse(R"({"a": {"b": 1}})");


assert(obj1 == obj2);
assert(obj1 != obj3);
assert(obj2 != obj3);

assert(obj3 == obj4);

// List Equal

json list1 = json::parse(R"([ 1, 2, []])");
json list2 = json::parse(R"([ 1, 2])");
json list3 = json::parse(R"([ 1, 2, []])");
json list4 = json::parse(R"([ 1, 2, {}])");

assert(list1 != list2);
assert(list1 == list3);
assert(list3 != list4);

}
 */

/*
   {
   json null = nullptr;


   std::cout << "null == nullptr: " << (null == nullptr) << std::endl;
   }
 */

/*
   {
   json ex1 = json::parse(R"(
   {
   "happy": true,
   "pi": 2
   }
   )");

   std::cout << isNode({ ex1 }) << std::endl;
   }

   {

   std::ifstream f("../build/test/test.json");
   json alltests = json::parse(f);

   std::cout << "spec: " << alltests["minor"]["isnode"] << std::endl;

   }
 */


/*
   {
   Struct _struct {new isList()};

   std::cout << _struct.islist->apply({ 1 }) << std::endl;
   std::cout << _struct.islist->apply({ json::array() }) << std::endl;
   std::cout << _struct.islist->apply({ json::object() }) << std::endl;

   }
 */


/*

   json ex1 = json::parse(R"(
   {
   "happy": true,
   "pi": 2
   }
   )");

   json j2 = {
   {"pi", 3.141},
   {"happy", true},
   {"name", "Niels"},
   {"nothing", nullptr},
   {"answer", {
   {"everything", 42}
   }},
   {"list", {1, 0, 2}},
   {"object", {
   {"currency", "USD"},
   {"value", 42.99}
   }}
   };

// Using initializer lists
json ex3 = {
{"happy", true},
{"pi", 3.141},
};

json happy = ex1.at("happy");


json list1 = json::parse("[ 1, \"a\"]");
const json& list2 = list1;

std::vector<json> vec1;

if(list1.is_array()) {
for(json::iterator it = list1.begin(); it != list1.end(); ++it) {
vec1.push_back(it.value());
}
}


std::cout << ex1.dump(2) << std::endl;
std::cout << happy << std::endl;
std::cout << ex1.is_object() << std::endl;

for(size_t i = 0; i < vec1.size(); i++) {
std::cout << "vec[i]: " << vec1[i] << std::endl;
}

// Deep Copy
{
json obj1 = json::parse("{\"a\": {\"1\": \"2\" }}");
json obj2 = obj1;

obj1["a"]["1"] = 3;


std::cout << obj1.dump(2) << std::endl;
std::cout << obj2.dump(2) << std::endl;
}
 */
}
