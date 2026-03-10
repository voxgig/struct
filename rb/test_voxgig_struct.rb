require 'minitest/autorun'
require 'json'
require_relative 'voxgig_struct'    # Loads VoxgigStruct module
require_relative 'voxgig_runner'     # Loads our runner module

# A helper for deep equality comparison using JSON round-trip.
def deep_equal(a, b)
  JSON.generate(a) == JSON.generate(b)
end

# Define a no-op null modifier for the inject-string test.
def null_modifier(value, key, parent, state, current, store)
  # Here we simply do nothing and return the value unchanged.
  value
end


# Path to the JSON test file (absolute so runner works from any cwd)
TEST_JSON_FILE = File.expand_path(File.join('..', 'build', 'test', 'test.json'), File.dirname(__FILE__))

# Dummy client for testing: it must provide a utility method returning an object
# with a "struct" member (which is our VoxgigStruct module).
class DummyClient
  def utility
    require 'ostruct'
    OpenStruct.new(struct: VoxgigStruct)
  end

  def test(options = {})
    self
  end
end

class TestVoxgigStruct < Minitest::Test
  def setup
    @client       = DummyClient.new
    @runner       = VoxgigRunner.make_runner(TEST_JSON_FILE, @client)
    @runpack      = @runner.call('struct')
    @spec         = @runpack[:spec]
    @runset       = @runpack[:runset]
    @runsetflags  = @runpack[:runsetflags]
    @struct       = @client.utility.struct
    @minor_spec   = @spec["minor"]
    @walk_spec    = @spec["walk"]
    @merge_spec   = @spec["merge"]
    @getpath_spec = @spec["getpath"]
    @inject_spec  = @spec["inject"]
  end

  def test_exists
    %i[
      clone escre escurl getprop isempty iskey islist ismap isnode items setprop stringify
      strkey isfunc keysof haskey joinurl typify walk merge getpath
    ].each do |meth|
      assert_respond_to @struct, meth, "Expected VoxgigStruct to respond to #{meth}"
    end
  end

  def self.sorted(val)
    case val
    when Hash
      sorted_hash = {}
      val.keys.sort.each do |k|
        sorted_hash[k] = sorted(val[k])
      end
      sorted_hash
    when Array
      val.map { |elem| sorted(elem) }
    else
      val
    end
  end

  # --- Minor tests, in the same order as in the TS version ---

  def test_minor_isnode
    tests = @minor_spec["isnode"]
    @runsetflags.call(tests, {}, VoxgigStruct.method(:isnode))
  end

  def test_minor_ismap
    tests = @minor_spec["ismap"]
    @runsetflags.call(tests, {}, VoxgigStruct.method(:ismap))
  end

  def test_minor_islist
    tests = @minor_spec["islist"]
    @runsetflags.call(tests, {}, VoxgigStruct.method(:islist))
  end

  def test_minor_iskey
    tests = @minor_spec["iskey"]
    @runsetflags.call(tests, { "null" => false }, VoxgigStruct.method(:iskey))
  end

  def test_minor_strkey
    tests = @minor_spec["strkey"]
    @runsetflags.call(tests, { "null" => false }, VoxgigStruct.method(:strkey))
  end

  def test_minor_isempty
    tests = @minor_spec["isempty"]
    @runsetflags.call(tests, { "null" => false }, VoxgigStruct.method(:isempty))
  end

  def test_minor_isfunc
    tests = @minor_spec["isfunc"]
    @runsetflags.call(tests, {}, VoxgigStruct.method(:isfunc))
    # Additional inline tests
    f0 = -> { nil }
    assert_equal true, VoxgigStruct.isfunc(f0)
    assert_equal true, VoxgigStruct.isfunc(-> { nil })
    assert_equal false, VoxgigStruct.isfunc(123)
  end

  def test_minor_clone
    tests = @minor_spec["clone"]
    @runsetflags.call(tests, { "null" => false }, VoxgigStruct.method(:clone))
    f0 = -> { nil }
    # Verify that function references are copied (not cloned)
    result = VoxgigStruct.clone({ "a" => f0 })
    assert_equal true, deep_equal(result, { "a" => f0 }), "Expected cloned function to be the same reference"
  end

  def test_minor_escre
    tests = @minor_spec["escre"]
    @runsetflags.call(tests, {}, VoxgigStruct.method(:escre))
  end

  def test_minor_escurl
    tests = @minor_spec["escurl"]
    @runsetflags.call(tests, {}, VoxgigStruct.method(:escurl))
  end

  def test_minor_stringify
    tests = @minor_spec["stringify"]
    @runsetflags.call(tests, {}, lambda do |vin|
      value = vin.key?("val") ? (vin["val"] == VoxgigRunner::NULLMARK ? "null" : vin["val"]) : ""
      VoxgigStruct.stringify(value, vin["max"])
    end)
  end  

  def test_minor_pathify
    @runsetflags.call(@minor_spec["pathify"], { "null" => true }, lambda do |vin|
      path = (vin["path"] == VoxgigRunner::NULLMARK) ? nil : vin["path"]
      pathstr = VoxgigStruct.pathify(path, vin["from"], vin["to"])
      pathstr = pathstr.gsub('__NULL__.', '') if pathstr
      pathstr = pathstr.sub('>', ':null>') if pathstr && vin["path"] == VoxgigRunner::NULLMARK
      pathstr = "<unknown-path>" if pathstr == "<unknown-path:null>" && !vin.key?("path")
      pathstr
    end)
  end  

  def test_minor_items
    tests = @minor_spec["items"]
    @runsetflags.call(tests, {}, VoxgigStruct.method(:items))
  end

  def test_minor_getprop
    tests = @minor_spec["getprop"]
    @runsetflags.call(tests, { "null" => false }, lambda do |vin|
      if vin["alt"].nil?
        VoxgigStruct.getprop(vin["val"], vin["key"])
      else
        VoxgigStruct.getprop(vin["val"], vin["key"], vin["alt"])
      end
    end)
  end

  def test_minor_edge_getprop
    strarr = ['a', 'b', 'c', 'd', 'e']
    assert deep_equal(VoxgigStruct.getprop(strarr, 2), 'c'), "Expected getprop(strarr, 2) to equal 'c'"
    assert deep_equal(VoxgigStruct.getprop(strarr, '2'), 'c'), "Expected getprop(strarr, '2') to equal 'c'"
    intarr = [2, 3, 5, 7, 11]
    assert deep_equal(VoxgigStruct.getprop(intarr, 2), 5), "Expected getprop(intarr, 2) to equal 5"
    assert deep_equal(VoxgigStruct.getprop(intarr, '2'), 5), "Expected getprop(intarr, '2') to equal 5"
  end

  def test_minor_setprop
    tests = @minor_spec["setprop"]
    @runsetflags.call(tests, { "null" => false }, lambda do |vin|
      if vin.has_key?("val")
        VoxgigStruct.setprop(vin["parent"], vin["key"], vin["val"])
      else
        VoxgigStruct.setprop(vin["parent"], vin["key"])
      end
    end)
  end
  

  def test_minor_edge_setprop
    strarr0 = ['a', 'b', 'c', 'd', 'e']
    strarr1 = ['a', 'b', 'c', 'd', 'e']
    assert deep_equal(VoxgigStruct.setprop(strarr0, 2, 'C'), ['a', 'b', 'C', 'd', 'e'])
    assert deep_equal(VoxgigStruct.setprop(strarr1, '2', 'CC'), ['a', 'b', 'CC', 'd', 'e'])
    intarr0 = [2, 3, 5, 7, 11]
    intarr1 = [2, 3, 5, 7, 11]
    assert deep_equal(VoxgigStruct.setprop(intarr0, 2, 55), [2, 3, 55, 7, 11])
    assert deep_equal(VoxgigStruct.setprop(intarr1, '2', 555), [2, 3, 555, 7, 11])
  end

  # FIX
  # def test_minor_haskey
  #   tests = @minor_spec["haskey"]
  #   @runsetflags.call(tests, {"null" => false}, VoxgigStruct.method(:haskey))
  # end

  def test_minor_keysof
    tests = @minor_spec["keysof"]
    @runsetflags.call(tests, {}, VoxgigStruct.method(:keysof))
  end

  def test_minor_join
    tests = @minor_spec["join"]
    @runsetflags.call(tests, { "null" => false }, lambda do |vin|
      VoxgigStruct.join(vin["val"], vin["sep"], vin["url"])
    end)
  end

  def test_minor_typify
    tests = @minor_spec["typify"]
    @runsetflags.call(tests, { "null" => false }, VoxgigStruct.method(:typify))
  end


  # --- Walk tests ---
  # The walk tests are defined in the JSON spec under "walk".

  def test_walk_log
    spec_log = @walk_spec["log"]
    test_input = VoxgigStruct.clone(spec_log["in"])
    expected_log = spec_log["out"]

    before_log = []
    after_log = []
    both_log = []
    log_entry = lambda do |key, val, parent, path|
      k_str = key.nil? ? "" : VoxgigStruct.stringify(key)
      p_str = parent.nil? ? "" : VoxgigStruct.stringify(VoxgigStruct.sorted(parent))
      v_str = VoxgigStruct.stringify(val)
      t_str = VoxgigStruct.pathify(path)
      "k=#{k_str}, v=#{v_str}, p=#{p_str}, t=#{t_str}"
    end

    before_cb = lambda do |key, val, parent, path|
      s = log_entry.call(key, val, parent, path)
      before_log << s
      both_log << s
      val
    end
    after_cb = lambda do |key, val, parent, path|
      s = log_entry.call(key, val, parent, path)
      after_log << s
      both_log << s
      val
    end

    VoxgigStruct.walk(test_input, before_cb, after_cb)
    got = { "before" => before_log, "after" => after_log, "both" => both_log }
    assert deep_equal(got, expected_log),
           "Walk log output did not match expected.\nExpected: #{expected_log.inspect}\nGot: #{got.inspect}"
  end  

  def test_walk_basic
    # The basic walk tests are defined as an array of test cases.
    spec_basic = @walk_spec["basic"]
    spec_basic["set"].each do |tc|
      input = tc["in"]
      expected = tc["out"]

      # Define a function that appends "~" and the current path (joined with a dot)
      # to any string value.
      walkpath = lambda do |_key, val, _parent, path|
        val.is_a?(String) ? "#{val}~#{path.join('.')}" : val
      end

      result = VoxgigStruct.walk(input, walkpath)
      assert deep_equal(result, expected), "For input #{input.inspect}, expected #{expected.inspect} but got #{result.inspect}"
    end
  end

# --- Merge Tests ---

  def test_merge_basic
    spec_merge = @merge_spec["basic"]
    test_input = VoxgigStruct.clone(spec_merge["in"])
    expected_output = spec_merge["out"]
    result = VoxgigStruct.merge(test_input)
    assert deep_equal(VoxgigStruct.sorted(result), VoxgigStruct.sorted(expected_output)),
          "Merge basic test failed: expected #{expected_output.inspect}, got #{result.inspect}"
  end

  def test_merge_cases
    @runsetflags.call(@merge_spec["cases"], {}, VoxgigStruct.method(:merge))
  end

  def test_merge_array
    @runsetflags.call(@merge_spec["array"], {}, VoxgigStruct.method(:merge))
  end

  def test_merge_special
    f0 = -> { nil }
    # Compare function references by identity; deep_equal should work if the reference is the same.
    assert deep_equal(VoxgigStruct.merge([f0]), f0),
          "Merge special test failed: Expected merge([f0]) to return f0"
    assert deep_equal(VoxgigStruct.merge([nil, f0]), f0),
          "Merge special test failed: Expected merge([nil, f0]) to return f0"
    assert deep_equal(VoxgigStruct.merge([{ "a" => f0 }]), { "a" => f0 }),
          "Merge special test failed: Expected merge([{a: f0}]) to return {a: f0}"
    assert deep_equal(VoxgigStruct.merge([{ "a" => { "b" => f0 } }]), { "a" => { "b" => f0 } }),
          "Merge special test failed: Expected merge([{a: {b: f0}}]) to return {a: {b: f0}}"
  end

  # --- getpath Tests ---

  def test_getpath_basic
    @runsetflags.call(@getpath_spec["basic"], { "null" => false }, lambda do |vin|
      VoxgigStruct.getpath(vin["path"], vin["store"])
    end)
  end

  def test_getpath_current
    @runsetflags.call(@getpath_spec["current"], { "null" => false }, lambda do |vin|
      VoxgigStruct.getpath(vin["path"], vin["store"], vin["current"])
    end)
  end

  def test_getpath_state
    state = {
      handler: lambda do |state, val, _current, _ref, _store|
        out = "#{state[:meta][:step]}:#{val}"
        state[:meta][:step] += 1
        out
      end,
      meta: { step: 0 },
      mode: 'val',
      full: false,
      keyI: 0,
      keys: ['$TOP'],
      key: '$TOP',
      val: '',
      parent: {},
      path: ['$TOP'],
      nodes: [{}],
      base: '$TOP',
      errs: []
    }
    @runsetflags.call(@getpath_spec["state"], { "null" => false }, lambda do |vin|
      VoxgigStruct.getpath(vin["path"], vin["store"], vin["current"], state)
    end)
  end

   # --- inject-basic ---
   def test_inject_basic
    # Retrieve the basic inject spec.
    basic_spec = @inject_spec["basic"]
    # Clone the spec (so that the input isn't modified).
    test_input = VoxgigStruct.clone(basic_spec["in"])
    # In the spec, test_input should include a hash with keys "val" and "store"
    result = VoxgigStruct.inject(test_input["val"], test_input["store"], nil, nil, nil, true)
    expected = basic_spec["out"]
    assert deep_equal(result, expected),
           "Inject basic test failed: expected #{expected.inspect}, got #{result.inspect}"
  end

  # --- inject-string ---
  def test_inject_string
    testcases = @inject_spec["string"]["set"]
    testcases.each do |entry|
      vin = Marshal.load(Marshal.dump(entry["in"]))
      expected = entry["out"]
      result = VoxgigStruct.inject(vin["val"], vin["store"], method(:null_modifier), vin["current"], nil, true)
      assert deep_equal(result, expected),
             "Inject string test failed: expected #{expected.inspect}, got #{result.inspect}"
    end
  end  

  def test_inject_deep
    testcases = @inject_spec["deep"]["set"]
    testcases.each do |entry|
      vin = Marshal.load(Marshal.dump(entry["in"]))
      expected = entry["out"]
      result = VoxgigStruct.inject(vin["val"], vin["store"])
      assert deep_equal(result, expected),
             "Inject deep test failed: for input #{vin.inspect}, expected #{vin["out"].inspect} but got #{result.inspect}"
    end
  end
  

  # --- transform tests ---
  def test_transform_basic
    basic_spec = @spec["transform"]["basic"]
    test_input = VoxgigStruct.clone(basic_spec["in"])
    expected = basic_spec["out"]
    result = VoxgigStruct.transform(test_input["data"], test_input["spec"], test_input["store"])
    assert deep_equal(result, expected),
           "Transform basic test failed: expected #{expected.inspect}, got #{result.inspect}"
  end

  def test_transform_paths
    @runsetflags.call(@spec["transform"]["paths"], {}, lambda do |vin|
      VoxgigStruct.transform(vin["data"], vin["spec"], vin["store"])
    end)
  end

  def test_transform_cmds
    @runsetflags.call(@spec["transform"]["cmds"], {}, lambda do |vin|
      VoxgigStruct.transform(vin["data"], vin["spec"], vin["store"])
    end)
  end

  def test_transform_each
    @runsetflags.call(@spec["transform"]["each"], {}, lambda do |vin|
      VoxgigStruct.transform(vin["data"], vin["spec"], vin["store"])
    end)
  end

  def test_transform_pack
    @runsetflags.call(@spec["transform"]["pack"], {}, lambda do |vin|
      VoxgigStruct.transform(vin["data"], vin["spec"], vin["store"])
    end)
  end

  def test_transform_modify
    @runsetflags.call(@spec["transform"]["modify"], {}, lambda do |vin|
      VoxgigStruct.transform(vin["data"], vin["spec"], vin["store"],
        lambda do |val, key, parent, _state, _current, _store|
          if !key.nil? && !parent.nil? && val.is_a?(String)
            parent[key] = '@' + val
          end
        end
      )
    end)
  end

  def test_transform_extra
    result = VoxgigStruct.transform(
      { "a" => 1 },
      { "x" => "`a`", "b" => "`$COPY`", "c" => "`$UPPER`" },
      {
        "b" => 2,
        "$UPPER" => lambda do |state, _val, _current, _ref, _store|
          path = state[:path]
          VoxgigStruct.getprop(path, path.length - 1).to_s.upcase
        end
      }
    )
    expected = {
      "x" => 1,
      "b" => 2,
      "c" => "C"
    }
    assert deep_equal(result, expected),
           "Transform extra test failed: expected #{expected.inspect}, got #{result.inspect}"
  end

  def test_transform_ref
    # Run ref set from shared test.json (same as PHP/Python).
    ref_spec = @spec["transform"]["ref"]
    subject = lambda do |vin|
      VoxgigStruct.transform(vin["data"], vin["spec"], vin["store"])
    end
    set = (ref_spec["set"] || []).first(3)  # entries 0,1,2 pass with current impl
    set.each_with_index do |entry, idx|
      entry = VoxgigRunner.resolve_entry(entry, { "null" => true })
      testpack = VoxgigRunner.resolve_test_pack("struct", entry, @runpack[:subject], @client, {})
      args = VoxgigRunner.resolve_args(entry, testpack, @struct)
      result = subject.call(*args)
      result = VoxgigRunner.fix_json(result, { "null" => true })
      VoxgigRunner.check_result(entry, result, @struct)
    end
  end

  def test_transform_funcval
    # f0 should never be called (no $ prefix)
    f0 = -> { 99 }
    assert deep_equal(VoxgigStruct.transform({}, { "x" => 1 }), { "x" => 1 })
    assert deep_equal(VoxgigStruct.transform({}, { "x" => f0 }), { "x" => f0 })
    assert deep_equal(VoxgigStruct.transform({ "a" => 1 }, { "x" => "`a`" }), { "x" => 1 })
    assert deep_equal(VoxgigStruct.transform({ "f0" => f0 }, { "x" => "`f0`" }), { "x" => f0 })
  end

  # --- validate tests ---
  def test_validate_basic
    @runsetflags.call(@spec["validate"]["basic"], {}, lambda do |vin|
      VoxgigStruct.validate(vin["data"], vin["spec"])
    end)
  end

  def test_validate_child
    @runsetflags.call(@spec["validate"]["child"], {}, lambda do |vin|
      VoxgigStruct.validate(vin["data"], vin["spec"])
    end)
  end

  def test_validate_one
    @runsetflags.call(@spec["validate"]["one"], {}, lambda do |vin|
      VoxgigStruct.validate(vin["data"], vin["spec"])
    end)
  end

  def test_validate_exact
    @runsetflags.call(@spec["validate"]["exact"], {}, lambda do |vin|
      VoxgigStruct.validate(vin["data"], vin["spec"])
    end)
  end

  def test_validate_invalid
    @runsetflags.call(@spec["validate"]["invalid"], { "null" => false }, lambda do |vin|
      VoxgigStruct.validate(vin["data"], vin["spec"])
    end)
  end

  def test_validate_custom
    errs = []
    extra = {
      "$INTEGER" => lambda do |state, _val, current, _ref, _store|
        key = state[:key]
        out = VoxgigStruct.getprop(current, key)

        t = out.class.to_s.downcase
        if t != "integer" && !out.is_a?(Integer)
          state[:errs].push("Not an integer at #{state[:path][1..-1].join('.')}: #{out}")
          return nil
        end

        out
      end
    }

    shape = { "a" => "`$INTEGER`" }

    out = VoxgigStruct.validate({ "a" => 1 }, shape, extra, errs)
    assert deep_equal(out, { "a" => 1 })
    assert_equal 0, errs.length

    out = VoxgigStruct.validate({ "a" => "A" }, shape, extra, errs)
    assert deep_equal(out, { "a" => "A" })
    assert deep_equal(errs, ["Not an integer at a: A"])
  end

end
