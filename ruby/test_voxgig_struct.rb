require 'minitest/autorun'
require 'json'
require_relative 'voxgig_struct' # Loads VoxgigStruct module
require_relative 'voxgig_runner' # Loads our runner module

# A helper for deep equality comparison using JSON round-trip.
def deep_equal(a, b)
  normalize = lambda { |v|
    case v
    when Hash
      sorted = {}
      v.keys.sort.each { |k| sorted[k] = normalize.call(v[k]) }
      sorted
    when Array
      v.map { |e| normalize.call(e) }
    else
      v
    end
  }
  JSON.generate(normalize.call(a)) == JSON.generate(normalize.call(b))
rescue StandardError
  a == b
end

# Path to the JSON test file
TEST_JSON_FILE = File.join(File.dirname(__FILE__), '..', 'build', 'test', 'test.json')

# Dummy client for testing
class DummyClient
  def utility
    require 'ostruct'
    OpenStruct.new(struct: VoxgigStruct)
  end

  def test(_options = {})
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
    @minor_spec     = @spec['minor']
    @walk_spec      = @spec['walk']
    @merge_spec     = @spec['merge']
    @getpath_spec   = @spec['getpath']
    @inject_spec    = @spec['inject']
    @sentinels_spec = @spec['sentinels']
  end

  def test_exists
    %i[
      clone delprop escre escurl filter flatten getdef getelem getpath getprop
      haskey inject isempty isfunc iskey islist ismap isnode items join jsonify
      keysof merge pad pathify select setpath setprop size slice strkey stringify
      transform typify typename validate walk jm jt
      checkPlacement injectorArgs injectChild
    ].each do |meth|
      assert_respond_to @struct, meth, "Expected VoxgigStruct to respond to #{meth}"
    end
  end

  # --- Minor tests ---

  def test_minor_isnode
    @runsetflags.call(@minor_spec['isnode'], {}, VoxgigStruct.method(:isnode))
  end

  def test_minor_ismap
    @runsetflags.call(@minor_spec['ismap'], {}, VoxgigStruct.method(:ismap))
  end

  def test_minor_islist
    @runsetflags.call(@minor_spec['islist'], {}, VoxgigStruct.method(:islist))
  end

  def test_minor_iskey
    @runsetflags.call(@minor_spec['iskey'], { 'null' => false }, VoxgigStruct.method(:iskey))
  end

  def test_minor_strkey
    @runsetflags.call(@minor_spec['strkey'], { 'null' => false }, VoxgigStruct.method(:strkey))
  end

  def test_minor_isempty
    @runsetflags.call(@minor_spec['isempty'], { 'null' => false }, VoxgigStruct.method(:isempty))
  end

  def test_minor_isfunc
    @runsetflags.call(@minor_spec['isfunc'], {}, VoxgigStruct.method(:isfunc))
    f0 = -> {}
    assert_equal true, VoxgigStruct.isfunc(f0)
    assert_equal false, VoxgigStruct.isfunc(123)
  end

  def test_minor_clone
    @runsetflags.call(@minor_spec['clone'], { 'null' => false }, VoxgigStruct.method(:clone))
    f0 = -> {}
    result = VoxgigStruct.clone({ 'a' => f0 })
    assert_equal true, deep_equal(result, { 'a' => f0 })
  end

  def test_minor_escre
    @runsetflags.call(@minor_spec['escre'], {}, VoxgigStruct.method(:escre))
  end

  def test_minor_escurl
    @runsetflags.call(@minor_spec['escurl'], {}, VoxgigStruct.method(:escurl))
  end

  def test_minor_stringify
    @runsetflags.call(@minor_spec['stringify'], {}, lambda { |vin|
      value = vin.key?('val') ? (vin['val'] == VoxgigRunner::NULLMARK ? 'null' : vin['val']) : ''
      VoxgigStruct.stringify(value, vin['max'])
    })
  end

  def test_minor_pathify
    @runsetflags.call(@minor_spec['pathify'], { 'null' => false }, lambda { |vin|
      path = vin.key?('path') ? vin['path'] : VoxgigStruct::UNDEF
      VoxgigStruct.pathify(path, vin['startin'] || vin['from'], vin['endin'])
    })
  end

  def test_minor_items
    @runsetflags.call(@minor_spec['items'], {}, VoxgigStruct.method(:items))
  end

  def test_minor_getprop
    @runsetflags.call(@minor_spec['getprop'], { 'null' => false }, lambda { |vin|
      if vin['alt'].nil?
        VoxgigStruct.getprop(vin['val'], vin['key'])
      else
        VoxgigStruct.getprop(vin['val'], vin['key'], vin['alt'])
      end
    })
  end

  def test_minor_getelem
    @runsetflags.call(@minor_spec['getelem'], { 'null' => false }, lambda { |vin|
      if vin.key?('alt')
        VoxgigStruct.getelem(vin['val'], vin['key'], vin['alt'])
      else
        VoxgigStruct.getelem(vin['val'], vin['key'])
      end
    })
  end

  def test_minor_edge_getprop
    strarr = %w[a b c d e]
    assert deep_equal(VoxgigStruct.getprop(strarr, 2), 'c')
    assert deep_equal(VoxgigStruct.getprop(strarr, '2'), 'c')
    intarr = [2, 3, 5, 7, 11]
    assert deep_equal(VoxgigStruct.getprop(intarr, 2), 5)
    assert deep_equal(VoxgigStruct.getprop(intarr, '2'), 5)
  end

  def test_minor_setprop
    @runsetflags.call(@minor_spec['setprop'], { 'null' => false }, lambda { |vin|
      if vin.key?('val')
        VoxgigStruct.setprop(vin['parent'], vin['key'], vin['val'])
      else
        VoxgigStruct.setprop(vin['parent'], vin['key'])
      end
    })
  end

  def test_minor_delprop
    @runsetflags.call(@minor_spec['delprop'], {}, lambda { |vin|
      VoxgigStruct.delprop(vin['parent'], vin['key'])
    })
  end

  def test_minor_edge_setprop
    strarr0 = %w[a b c d e]
    strarr1 = %w[a b c d e]
    assert deep_equal(VoxgigStruct.setprop(strarr0, 2, 'C'), %w[a b C d e])
    assert deep_equal(VoxgigStruct.setprop(strarr1, '2', 'CC'), %w[a b CC d e])
  end

  def test_minor_haskey
    @runsetflags.call(@minor_spec['haskey'], { 'null' => false }, lambda { |vin|
      VoxgigStruct.haskey(vin['src'], vin['key'])
    })
  end

  def test_minor_keysof
    @runsetflags.call(@minor_spec['keysof'], {}, VoxgigStruct.method(:keysof))
  end

  def test_minor_join
    @runsetflags.call(@minor_spec['join'], { 'null' => false }, lambda { |vin|
      VoxgigStruct.join(vin['val'], vin['sep'], vin['url'])
    })
  end

  def test_minor_jsonify
    @runsetflags.call(@minor_spec['jsonify'], { 'null' => false }, lambda { |vin|
      VoxgigStruct.jsonify(vin['val'], vin['flags'])
    })
  end

  def test_minor_flatten
    @runsetflags.call(@minor_spec['flatten'], {}, lambda { |vin|
      VoxgigStruct.flatten(vin['val'], vin['depth'])
    })
  end

  def test_minor_filter
    checks = {
      'gt3' => ->(item) { item[1].is_a?(Numeric) && item[1] > 3 },
      'lt3' => ->(item) { item[1].is_a?(Numeric) && item[1] < 3 }
    }
    @runsetflags.call(@minor_spec['filter'], {}, lambda { |vin|
      check = checks[vin['check']] || ->(_item) { true }
      VoxgigStruct.filter(vin['val'], check)
    })
  end

  def test_minor_typename
    @runsetflags.call(@minor_spec['typename'], {}, VoxgigStruct.method(:typename))
  end

  def test_minor_typify
    @runsetflags.call(@minor_spec['typify'], { 'null' => false }, VoxgigStruct.method(:typify))
  end

  def test_minor_size
    @runsetflags.call(@minor_spec['size'], { 'null' => false }, VoxgigStruct.method(:size))
  end

  def test_minor_slice
    @runsetflags.call(@minor_spec['slice'], { 'null' => false }, lambda { |vin|
      VoxgigStruct.slice(vin['val'], vin['start'], vin['end'])
    })
  end

  def test_minor_pad
    # pad is Group B: stringify(null) renders as "null". With the
    # runner's nested NULLMARK substitution turned on, the corpus
    # null value arrives as the marker string — convert it back to
    # the literal "null" so pad's output matches the corpus shape.
    @runsetflags.call(@minor_spec['pad'], {}, lambda { |vin|
      v = vin['val']
      v = 'null' if v == VoxgigRunner::NULLMARK
      VoxgigStruct.pad(v, vin['pad'], vin['char'])
    })
  end

  def test_minor_setpath
    @runsetflags.call(@minor_spec['setpath'], {}, lambda { |vin|
      VoxgigStruct.setpath(vin['store'], vin['path'], vin['val'])
    })
  end

  def test_minor_getdef
    assert_equal 1, VoxgigStruct.getdef(1, 2)
    assert_equal 2, VoxgigStruct.getdef(nil, 2)
    assert_equal 'a', VoxgigStruct.getdef('a', 'b')
    assert_equal 'b', VoxgigStruct.getdef(nil, 'b')
  end

  # --- Sentinels tests (Group A null/absent unification, UNDEF_SPEC.md) ---
  #
  # These exercise the readers against a stored JSON null. The runner's
  # nested NULLMARK substitution is turned OFF ({ 'null' => false }) so the
  # corpus's real `null` reaches the function as a genuine nil — otherwise
  # the marker string would mask the very null-handling this group checks.

  def test_sentinels_getprop_unify
    @runsetflags.call(@sentinels_spec['getprop_unify'], { 'null' => false }, lambda { |vin|
      VoxgigStruct.getprop(vin['val'], vin['key'], vin['alt'])
    })
  end

  def test_sentinels_getelem_absent
    @runsetflags.call(@sentinels_spec['getelem_absent'], { 'null' => false }, lambda { |vin|
      VoxgigStruct.getelem(vin['val'], vin['key'], vin['alt'])
    })
  end

  def test_sentinels_haskey_unify
    @runsetflags.call(@sentinels_spec['haskey_unify'], { 'null' => false }, lambda { |vin|
      VoxgigStruct.haskey(vin['val'], vin['key'])
    })
  end

  def test_sentinels_isempty_unify
    @runsetflags.call(@sentinels_spec['isempty_unify'], { 'null' => false }, VoxgigStruct.method(:isempty))
  end

  def test_sentinels_isnode_unify
    @runsetflags.call(@sentinels_spec['isnode_unify'], { 'null' => false }, VoxgigStruct.method(:isnode))
  end

  def test_sentinels_stringify_null
    @runsetflags.call(@sentinels_spec['stringify_null'], { 'null' => false }, lambda { |vin|
      VoxgigStruct.stringify(vin)
    })
  end

  # --- Walk tests ---

  def test_walk_log
    spec_log = @walk_spec['log']
    test_input = VoxgigStruct.clone(spec_log['in'])
    expected_log = spec_log['out']

    log = []

    walklog = lambda do |key, val, parent, path|
      k_str = key.nil? ? '' : VoxgigStruct.stringify(key)
      p_str = parent.nil? ? '' : VoxgigStruct.stringify(parent)
      v_str = VoxgigStruct.stringify(val)
      t_str = VoxgigStruct.pathify(path)
      log << "k=#{k_str}, v=#{v_str}, p=#{p_str}, t=#{t_str}"
      val
    end

    # after only
    VoxgigStruct.walk(test_input, nil, walklog)
    assert deep_equal(log, expected_log['after']),
           "Walk log (after) failed.\nExpected: #{expected_log['after'].inspect}\nGot: #{log.inspect}"

    log = []
    test_input = VoxgigStruct.clone(spec_log['in'])
    # before only
    VoxgigStruct.walk(test_input, walklog)
    assert deep_equal(log, expected_log['before']),
           "Walk log (before) failed.\nExpected: #{expected_log['before'].inspect}\nGot: #{log.inspect}"

    log = []
    test_input = VoxgigStruct.clone(spec_log['in'])
    # both
    VoxgigStruct.walk(test_input, walklog, walklog)
    assert deep_equal(log, expected_log['both']),
           "Walk log (both) failed.\nExpected: #{expected_log['both'].inspect}\nGot: #{log.inspect}"
  end

  def test_walk_basic
    spec_basic = @walk_spec['basic']
    spec_basic['set'].each do |tc|
      input = tc['in']
      expected = tc['out']

      walkpath = lambda do |_key, val, _parent, path|
        val.is_a?(String) ? "#{val}~#{path.join('.')}" : val
      end

      result = VoxgigStruct.walk(input, walkpath)
      assert deep_equal(result, expected), "Walk basic: expected #{expected.inspect}, got #{result.inspect}"
    end
  end

  def test_walk_depth
    @runsetflags.call(@walk_spec['depth'], { 'null' => false }, lambda { |vin|
      top = nil
      cur = nil
      copy = lambda { |key, val, _parent, _path|
        if key.nil? || VoxgigStruct.isnode(val)
          child = VoxgigStruct.islist(val) ? [] : {}
          if key.nil?
            top = cur = child
          else
            cur[key.is_a?(String) ? key : key.to_s] = child
            cur = child
          end
        else
          cur[key.is_a?(String) ? key : key.to_s] = val
        end
        val
      }
      VoxgigStruct.walk(vin['src'], copy, nil, vin['maxdepth'])
      top
    })
  end

  def test_walk_copy
    cur = []
    walkcopy = lambda { |key, val, _parent, path|
      if key.nil?
        cur = []
        cur[0] = VoxgigStruct.ismap(val) ? {} : VoxgigStruct.islist(val) ? [] : val
        next val
      end
      v = val
      i = VoxgigStruct.size(path)
      if VoxgigStruct.isnode(v)
        v = VoxgigStruct.ismap(v) ? {} : []
        cur[i] = v
      end
      VoxgigStruct.setprop(cur[i - 1], key, v)
      val
    }
    @runsetflags.call(@walk_spec['copy'], {}, lambda { |vin|
      VoxgigStruct.walk(vin, walkcopy)
      cur[0]
    })
  end

  # --- Merge tests ---

  def test_merge_basic
    spec_merge = @merge_spec['basic']
    test_input = VoxgigStruct.clone(spec_merge['in'])
    expected_output = spec_merge['out']
    result = VoxgigStruct.merge(test_input)
    assert deep_equal(result, expected_output),
           "Merge basic: expected #{expected_output.inspect}, got #{result.inspect}"
  end

  def test_merge_cases
    @runsetflags.call(@merge_spec['cases'], {}, VoxgigStruct.method(:merge))
  end

  def test_merge_array
    @runsetflags.call(@merge_spec['array'], {}, VoxgigStruct.method(:merge))
  end

  def test_merge_integrity
    @runsetflags.call(@merge_spec['integrity'], {}, VoxgigStruct.method(:merge))
  end

  def test_merge_depth
    @runsetflags.call(@merge_spec['depth'], {}, lambda { |vin|
      VoxgigStruct.merge(vin['val'], vin['depth'])
    })
  end

  def test_merge_special
    f0 = -> {}
    assert deep_equal(VoxgigStruct.merge([f0]), f0)
    assert deep_equal(VoxgigStruct.merge([nil, f0]), f0)
    assert deep_equal(VoxgigStruct.merge([{ 'a' => f0 }]), { 'a' => f0 })
    assert deep_equal(VoxgigStruct.merge([{ 'a' => { 'b' => f0 } }]), { 'a' => { 'b' => f0 } })
  end

  # --- getpath tests ---

  def test_getpath_basic
    @runsetflags.call(@getpath_spec['basic'], { 'null' => false }, lambda { |vin|
      VoxgigStruct.getpath(vin['store'], vin['path'])
    })
  end

  def test_getpath_relative
    @runsetflags.call(@getpath_spec['relative'], { 'null' => false }, lambda { |vin|
      injdef = {}
      injdef['dparent'] = vin['dparent'] if vin.key?('dparent')
      injdef['dpath'] = vin['dpath'].split('.') if vin.key?('dpath') && vin['dpath'].is_a?(String)
      injdef['dpath'] = vin['dpath'] if vin.key?('dpath') && vin['dpath'].is_a?(Array)
      VoxgigStruct.getpath(vin['store'], vin['path'], injdef)
    })
  end

  def test_getpath_handler
    @runsetflags.call(@getpath_spec['handler'], { 'null' => false }, lambda { |vin|
      store = {
        '$TOP' => vin['store'],
        '$FOO' => -> { 'foo' }
      }
      injdef = {
        'handler' => lambda { |_inj, val, _ref, _store|
          val.respond_to?(:call) ? val.call : val
        }
      }
      VoxgigStruct.getpath(store, vin['path'], injdef)
    })
  end

  def test_getpath_special
    @runsetflags.call(@getpath_spec['special'], { 'null' => false }, lambda { |vin|
      injdef = vin.key?('inj') ? vin['inj'] : nil
      VoxgigStruct.getpath(vin['store'], vin['path'], injdef)
    })
  end

  # --- inject tests ---

  def test_inject_basic
    basic_spec = @inject_spec['basic']
    test_input = VoxgigStruct.clone(basic_spec['in'])
    result = VoxgigStruct.inject(test_input['val'], test_input['store'])
    expected = basic_spec['out']
    assert deep_equal(result, expected),
           "Inject basic: expected #{expected.inspect}, got #{result.inspect}"
  end

  def test_inject_string
    testcases = @inject_spec['string']['set']
    testcases.each do |entry|
      vin = VoxgigStruct.clone(entry['in'])
      expected = entry['out']
      result = VoxgigStruct.inject(vin['val'], vin['store'])
      assert deep_equal(result, expected),
             "Inject string: expected #{expected.inspect}, got #{result.inspect}"
    end
  end

  def test_inject_deep
    testcases = @inject_spec['deep']['set']
    testcases.each do |entry|
      vin = VoxgigStruct.clone(entry['in'])
      expected = entry['out']
      result = VoxgigStruct.inject(vin['val'], vin['store'])
      assert deep_equal(result, expected),
             "Inject deep: expected #{expected.inspect}, got #{result.inspect}"
    end
  end

  # --- transform tests ---

  def test_transform_basic
    basic_spec = @spec['transform']['basic']
    test_input = VoxgigStruct.clone(basic_spec['in'])
    expected = basic_spec['out']
    result = VoxgigStruct.transform(test_input['data'], test_input['spec'])
    assert deep_equal(result, expected),
           "Transform basic: expected #{expected.inspect}, got #{result.inspect}"
  end

  def test_transform_paths
    @runsetflags.call(@spec['transform']['paths'], {}, lambda { |vin|
      VoxgigStruct.transform(vin['data'], vin['spec'])
    })
  end

  def test_transform_cmds
    @runsetflags.call(@spec['transform']['cmds'], {}, lambda { |vin|
      VoxgigStruct.transform(vin['data'], vin['spec'])
    })
  end

  def test_transform_each
    @runsetflags.call(@spec['transform']['each'], {}, lambda { |vin|
      VoxgigStruct.transform(vin['data'], vin['spec'])
    })
  end

  def test_transform_pack
    @runsetflags.call(@spec['transform']['pack'], {}, lambda { |vin|
      VoxgigStruct.transform(vin['data'], vin['spec'])
    })
  end

  def test_transform_ref
    @runsetflags.call(@spec['transform']['ref'], {}, lambda { |vin|
      VoxgigStruct.transform(vin['data'], vin['spec'])
    })
  end

  def test_transform_format
    @runsetflags.call(@spec['transform']['format'], { 'null' => false }, lambda { |vin|
      VoxgigStruct.transform(vin['data'], vin['spec'])
    })
  end

  def test_transform_apply
    @runsetflags.call(@spec['transform']['apply'], {}, lambda { |vin|
      VoxgigStruct.transform(vin['data'], vin['spec'])
    })
  end

  def test_transform_edge_apply
    result = VoxgigStruct.transform({}, ['`$APPLY`', ->(v, _s, _i) { 1 + v }, 1])
    assert_equal 2, result
  end

  def test_transform_modify
    @runsetflags.call(@spec['transform']['modify'], {}, lambda { |vin|
      VoxgigStruct.transform(
        vin['data'],
        vin['spec'],
        {
          'modify' => lambda { |val, key, parent, *_rest|
            parent[key.to_s] = "@#{val}" if !key.nil? && !parent.nil? && val.is_a?(String)
          }
        }
      )
    })
  end

  def test_transform_extra
    result = VoxgigStruct.transform(
      { 'a' => 1 },
      { 'x' => '`a`', 'b' => '`$COPY`', 'c' => '`$UPPER`' },
      {
        'extra' => {
          'b' => 2,
          '$UPPER' => lambda { |inj, *_args|
            path = inj.path
            VoxgigStruct.getprop(path, path.length - 1).to_s.upcase
          }
        }
      }
    )
    expected = { 'x' => 1, 'b' => 2, 'c' => 'C' }
    assert deep_equal(result, expected),
           "Transform extra: expected #{expected.inspect}, got #{result.inspect}"
  end

  def test_transform_funcval
    f0 = -> { 99 }
    assert deep_equal(VoxgigStruct.transform({}, { 'x' => 1 }), { 'x' => 1 })
    assert deep_equal(VoxgigStruct.transform({}, { 'x' => f0 }), { 'x' => f0 })
    assert deep_equal(VoxgigStruct.transform({ 'a' => 1 }, { 'x' => '`a`' }), { 'x' => 1 })
    assert deep_equal(VoxgigStruct.transform({ 'f0' => f0 }, { 'x' => '`f0`' }), { 'x' => f0 })
  end

  # --- validate tests ---

  def test_validate_basic
    @runsetflags.call(@spec['validate']['basic'], { 'null' => false }, lambda { |vin|
      VoxgigStruct.validate(vin['data'], vin['spec'])
    })
  end

  def test_validate_child
    @runsetflags.call(@spec['validate']['child'], {}, lambda { |vin|
      VoxgigStruct.validate(vin['data'], vin['spec'])
    })
  end

  def test_validate_one
    @runsetflags.call(@spec['validate']['one'], {}, lambda { |vin|
      VoxgigStruct.validate(vin['data'], vin['spec'])
    })
  end

  def test_validate_exact
    @runsetflags.call(@spec['validate']['exact'], {}, lambda { |vin|
      VoxgigStruct.validate(vin['data'], vin['spec'])
    })
  end

  def test_validate_invalid
    @runsetflags.call(@spec['validate']['invalid'], { 'null' => false }, lambda { |vin|
      VoxgigStruct.validate(vin['data'], vin['spec'])
    })
  end

  def test_validate_special
    @runsetflags.call(@spec['validate']['special'], {}, lambda { |vin|
      injdef = vin.key?('inj') ? vin['inj'] : nil
      VoxgigStruct.validate(vin['data'], vin['spec'], injdef)
    })
  end

  def test_validate_edge
    errs = []
    VoxgigStruct.validate({ 'x' => 1 }, { 'x' => '`$INSTANCE`' }, { 'errs' => errs })
    assert_equal 'Expected field x to be instance, but found integer: 1.', errs[0]
  end

  def test_validate_custom
    errs = []
    extra = {
      '$INTEGER' => lambda { |inj, *_args|
        key = inj.key
        out = VoxgigStruct.getprop(inj.dparent, key)

        t = VoxgigStruct.typify(out)
        if VoxgigStruct::T_integer.nobits?(t)
          inj.errs.push("Not an integer at #{inj.path[1..].join('.')}: #{out}")
          return nil
        end
        out
      }
    }

    shape = { 'a' => '`$INTEGER`' }

    out = VoxgigStruct.validate({ 'a' => 1 }, shape, { 'extra' => extra, 'errs' => errs })
    assert deep_equal(out, { 'a' => 1 })
    assert_equal 0, errs.length

    out = VoxgigStruct.validate({ 'a' => 'A' }, shape, { 'extra' => extra, 'errs' => errs })
    assert deep_equal(out, { 'a' => 'A' })
    assert deep_equal(errs, ['Not an integer at a: A'])
  end

  # --- select tests ---

  def test_select_basic
    @runsetflags.call(@spec['select']['basic'], {}, lambda { |vin|
      VoxgigStruct.select(vin['obj'], vin['query'])
    })
  end

  def test_select_operators
    @runsetflags.call(@spec['select']['operators'], {}, lambda { |vin|
      VoxgigStruct.select(vin['obj'], vin['query'])
    })
  end

  def test_select_edge
    @runsetflags.call(@spec['select']['edge'], {}, lambda { |vin|
      VoxgigStruct.select(vin['obj'], vin['query'])
    })
  end

  def test_select_alts
    @runsetflags.call(@spec['select']['alts'], {}, lambda { |vin|
      VoxgigStruct.select(vin['obj'], vin['query'])
    })
  end

  # --- json-builder tests ---

  def test_json_builder
    assert deep_equal(VoxgigStruct.jm('a', 1), { 'a' => 1 })
    assert deep_equal(VoxgigStruct.jm('a', 1, 'b', 2), { 'a' => 1, 'b' => 2 })
    assert deep_equal(VoxgigStruct.jt(1, 2, 3), [1, 2, 3])
    assert deep_equal(VoxgigStruct.jt, [])
  end

  # --- Injection.setval: UNDEF vs nil sentinel tests ---
  #
  # These tests bypass the corpus runner and exercise Injection.setval
  # directly with real nil / UNDEF values at both ancestor levels.
  # Before the sentinel refactor Ruby had a "MIXED" branch:
  #   nil + ancestor>=2 → setprop(grandparent, key, nil)  (preserved key)
  #   nil + ancestor<2  → delprop                          (removed key)
  # The runner masked the discrepancy by only ever passing the marker
  # string "__NULL__" at validator slots. These tests cover the path
  # the runner skipped, so a future regression would surface here.

  def test_setval_undef_deletes_parent_slot
    parent = { 'a' => 1, 'b' => 2 }
    inj = VoxgigStruct::Injection.new(nil, parent)
    inj.key = 'b'
    inj.parent = parent
    inj.path = ['', 'b']
    inj.nodes = [{ '$TOP' => parent }, parent]
    inj.setval(VoxgigStruct::UNDEF)
    assert_equal({ 'a' => 1 }, parent)
  end

  def test_setval_nil_deletes_parent_slot
    parent = { 'a' => 1, 'b' => 2 }
    inj = VoxgigStruct::Injection.new(nil, parent)
    inj.key = 'b'
    inj.parent = parent
    inj.path = ['', 'b']
    inj.nodes = [{ '$TOP' => parent }, parent]
    inj.setval(nil)
    assert_equal({ 'a' => 1 }, parent)
  end

  def test_setval_undef_deletes_ancestor_slot
    # ancestor=2: must remove the slot in @nodes[-2] at @path[-2].
    grand = { 'x' => { 'y' => 9 } }
    middle = grand['x']
    inj = VoxgigStruct::Injection.new(nil, middle)
    inj.key = 'y'
    inj.parent = middle
    inj.path = ['', 'x', 'y']
    inj.nodes = [{ '$TOP' => grand }, grand, middle]
    inj.setval(VoxgigStruct::UNDEF, 2)
    assert_equal({}, grand)
  end

  def test_setval_nil_at_ancestor2_also_deletes
    # Before the refactor this branch SET nil instead of deleting,
    # which only worked because the runner substituted nested null
    # → "__NULL__" string before reaching this path.
    grand = { 'x' => { 'y' => 9 } }
    middle = grand['x']
    inj = VoxgigStruct::Injection.new(nil, middle)
    inj.key = 'y'
    inj.parent = middle
    inj.path = ['', 'x', 'y']
    inj.nodes = [{ '$TOP' => grand }, grand, middle]
    inj.setval(nil, 2)
    assert_equal({}, grand)
  end

  def test_setval_value_sets_parent_slot
    parent = { 'a' => 1 }
    inj = VoxgigStruct::Injection.new(nil, parent)
    inj.key = 'b'
    inj.parent = parent
    inj.path = ['', 'b']
    inj.nodes = [{ '$TOP' => parent }, parent]
    inj.setval('X')
    assert_equal({ 'a' => 1, 'b' => 'X' }, parent)
  end

  # validate(nil, ['`$EXACT`', nil]) is the precise corpus case that
  # the old MIXED branch was tailored for. With the runner now doing
  # nested NULLMARK substitution and setval treating nil/UNDEF
  # uniformly as delete, the substituted "__NULL__" string flows
  # through and validation succeeds without error.

  def test_validate_exact_nil_against_nil_no_errors
    errs = []
    VoxgigStruct.validate(nil, ['`$EXACT`', nil], { 'errs' => errs })
    assert_equal [], errs
  end
end
