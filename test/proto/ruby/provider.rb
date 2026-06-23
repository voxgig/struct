# Test Provider (prototype) — Ruby port.
#
# Reads the shared corpus (build/test/test.json) and hands test code clean,
# normalized cases. It is NOT a test runner: it never calls the subject and
# never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
#
# Zero runtime dependencies (Ruby stdlib only).

require 'json'

class TestProvider
  NULLMARK = '__NULL__'.freeze
  UNDEFMARK = '__UNDEF__'.freeze
  EXISTSMARK = '__EXISTS__'.freeze

  attr_reader :spec

  def initialize(spec)
    @spec = spec
  end

  # Default corpus path: build/test/test.json relative to the repo root.
  def self.default_test_file
    File.join(__dir__, '..', '..', '..', 'build', 'test', 'test.json')
  end

  def self.load(path = nil)
    file = path || default_test_file
    new(JSON.parse(File.read(file)))
  end

  def raw
    @spec
  end

  def functions
    root = root_node
    root.keys.select { |k| self.class.group_bag?(root[k]) || self.class.has_groups?(root[k]) }
  end

  def groups(fn)
    node = fn_node(fn)
    node.keys.select { |k| k != 'name' && self.class.group_bag?(node[k]) }
  end

  def entries(fn, group = nil)
    node = fn_node(fn)
    gs = group.nil? ? groups(fn) : [group]
    out = []
    gs.each do |g|
      bag = node[g]
      next unless self.class.group_bag?(bag)

      set = bag['set']
      set.each_with_index do |raw_entry, i|
        out << self.class.normalize(fn, g, i, raw_entry)
      end
    end
    out
  end

  private

  def root_node
    (@spec.is_a?(Hash) && @spec['struct']) || @spec
  end

  def fn_node(fn)
    node = nil
    node = @spec['struct'][fn] if @spec.is_a?(Hash) && @spec['struct'].is_a?(Hash)
    node = @spec[fn] if node.nil? && @spec.is_a?(Hash)
    raise "Unknown function: #{fn}" if node.nil?

    node
  end

  # ─── structural predicates ────────────────────────────────────────────────

  # A group bag is a map with a `set` array.
  def self.group_bag?(v)
    v.is_a?(Hash) && v['set'].is_a?(Array)
  end

  # A function node has at least one child group bag.
  def self.has_groups?(v)
    v.is_a?(Hash) && v.keys.any? { |k| k != 'name' && group_bag?(v[k]) }
  end

  # ─── normalization ────────────────────────────────────────────────────────

  def self.normalize(fn, group, index, raw)
    {
      function: fn,
      group: group,
      index: index,
      id: raw.key?('id') && !raw['id'].nil? ? raw['id'].to_s : nil,
      doc: raw['doc'] == true,
      client: raw.key?('client') && !raw['client'].nil? ? raw['client'].to_s : nil,
      input: resolve_input(raw),
      expect: resolve_expect(raw),
      raw: raw
    }
  end

  def self.resolve_input(raw)
    return { kind: 'ctx', ctx: raw['ctx'] } if raw.key?('ctx')
    return { kind: 'args', args: raw['args'] } if raw.key?('args')

    { kind: 'in', in: raw.key?('in') ? raw['in'] : nil }
  end

  def self.parse_err(err)
    return { any: true, text: nil, regex: false } if err == true

    if err.is_a?(String)
      m = err.match(%r{\A/(.+)/\z})
      return { any: false, text: m[1], regex: true } if m

      return { any: false, text: err, regex: false }
    end

    # Non-true, non-string err spec: treat as "any error".
    { any: true, text: nil, regex: false }
  end

  def self.resolve_expect(raw)
    match_part = raw.key?('match') ? raw['match'] : nil
    return { kind: 'error', error: parse_err(raw['err']), match: match_part } if raw.key?('err')
    return { kind: 'value', value: raw['out'], match: match_part } if raw.key?('out')
    return { kind: 'match', match: raw['match'] } if raw.key?('match')

    { kind: 'absent' }
  end

  # ─── pure comparison helpers ──────────────────────────────────────────────

  def self.stringify(x)
    x.is_a?(String) ? x : x.to_json
  end

  def self.norm_null(x)
    return nil if x == NULLMARK || x.nil?
    return x.map { |v| norm_null(v) } if x.is_a?(Array)

    if x.is_a?(Hash)
      o = {}
      x.each_key { |k| o[k] = norm_null(x[k]) }
      return o
    end
    x
  end

  def self.norm_mark(x)
    return nil if x == NULLMARK
    return x.map { |v| norm_mark(v) } if x.is_a?(Array)

    if x.is_a?(Hash)
      o = {}
      x.each_key { |k| o[k] = norm_mark(x[k]) }
      return o
    end
    x
  end

  def self.deep_eq(a, b)
    return true if a.equal?(b)
    # Guard true/false vs 1: Ruby true != 1 already, so == is safe here.
    return true if a == b && same_kind?(a, b)

    if a.is_a?(Array) && b.is_a?(Array)
      return false unless a.length == b.length

      return a.each_index.all? { |i| deep_eq(a[i], b[i]) }
    end

    if a.is_a?(Hash) && b.is_a?(Hash)
      return false unless a.keys.length == b.keys.length

      return a.keys.all? { |k| b.key?(k) && deep_eq(a[k], b[k]) }
    end

    false
  end

  # Distinguish e.g. true vs 1, nil vs false where Ruby == would already
  # separate them, but be explicit for primitive identity comparisons.
  def self.same_kind?(a, b)
    return a.equal?(b) if [true, false, nil].include?(a) || [true, false, nil].include?(b)

    true
  end
  private_class_method :same_kind?

  def self.matchval(check, base)
    return true if check == base && same_kind?(check, base)

    if check.is_a?(String)
      basestr = stringify(base)
      m = check.match(%r{\A/(.+)/\z})
      return Regexp.new(m[1]).match?(basestr) if m

      return basestr.downcase.include?(check.downcase)
    end

    return true if check.respond_to?(:call)

    false
  end

  def self.equal(expected, actual)
    deep_eq(norm_null(expected), norm_null(actual))
  end

  # Strict variant for the runner's `{ null: false }` functions, where an absent
  # value (undefined) is distinct from JSON null. Only __NULL__ is normalized.
  def self.equal_strict(expected, actual)
    deep_eq(norm_mark(expected), norm_mark(actual))
  end

  def self.error_matches(check, message)
    return true if check[:any]
    return false if check[:text].nil?
    return Regexp.new(check[:text]).match?(message) if check[:regex]

    message.downcase.include?(check[:text].downcase)
  end

  def self.node?(v)
    v.is_a?(Hash) || v.is_a?(Array)
  end

  def self.walk_leaves(node, path, &block)
    if node.is_a?(Array)
      node.each_with_index { |v, i| walk_leaves(v, path + [i.to_s], &block) }
    elsif node.is_a?(Hash)
      node.each_key { |k| walk_leaves(node[k], path + [k], &block) }
    else
      block.call(node, path)
    end
  end

  # Sentinel distinguishing JS `undefined` (absent) from JSON null (present nil).
  UNDEF = Object.new.freeze

  def self.getpath(store, path)
    cur = store
    path.each do |key|
      return UNDEF if cur.nil? || cur.equal?(UNDEF)

      if cur.is_a?(Array)
        idx = key.to_i
        return UNDEF if idx.negative? || idx >= cur.length

        cur = cur[idx]
      elsif cur.is_a?(Hash)
        return UNDEF unless cur.key?(key)

        cur = cur[key]
      else
        return UNDEF
      end
    end
    cur
  end

  # Partial structural match: every leaf of `check` must match `base` at its path.
  def self.struct_match(check, base)
    result = { ok: true }
    walk_leaves(check, []) do |val, path|
      next unless result[:ok]

      baseval = getpath(base, path)
      undef_base = baseval.equal?(UNDEF)
      actual = undef_base ? nil : baseval

      next if !undef_base && baseval == val && same_kind?(baseval, val)
      next if val == UNDEFMARK && undef_base
      next if val == EXISTSMARK && !undef_base && !actual.nil?

      unless matchval(val, actual)
        result = { ok: false, path: path, expected: val, actual: actual }
      end
    end
    result
  end
end
