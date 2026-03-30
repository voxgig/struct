# voxgig_runner.rb
require 'json'
require 'pathname'

module VoxgigRunner
  NULLMARK = "__NULL__"    # Represents a JSON null in tests
  UNDEFMARK = "__UNDEF__"  # Represents an undefined value

  # make_runner(testfile, client)
  # Returns a lambda that accepts a name (e.g. "struct") and an optional store,
  # and returns a hash (runpack) with:
  #   :spec         -> the extracted spec for that name,
  #   :runset       -> a lambda to run a test set without extra flags,
  #   :runsetflags  -> a lambda to run a test set with flags,
  #   :subject      -> the function (or object method) under test,
  #   :client       -> the client instance.
  def self.make_runner(testfile, client)
    lambda do |name, store = {}|
      store ||= {}

      utility = client.utility
      struct_utils = utility.struct

      spec = resolve_spec(name, testfile)
      clients = resolve_clients(client, spec, store, struct_utils)
      subject = resolve_subject(name, utility)

      runsetflags = lambda do |testspec, flags, testsubject|
        subject = testsubject || subject
        flags = resolve_flags(flags)
        testspecmap = fix_json(testspec, flags)
        testset = (testspecmap && testspecmap["set"]) || []
        testset.each do |entry|
          begin
            entry = resolve_entry(entry, flags)
            # Log the test entry details if DEBUG is enabled.
            puts "DEBUG: Running test entry: in=#{entry['in'].inspect} expected=#{entry['out'].inspect}" if ENV['DEBUG']
            testpack = resolve_test_pack(name, entry, subject, client, clients)
            args = resolve_args(entry, testpack, struct_utils)
            # Log the arguments passed to subject.
            puts "DEBUG: Arguments for subject: #{args.inspect}" if ENV['DEBUG']
            # In Ruby we assume the subject is a Proc/lambda or a callable object.
            res = testpack[:subject].call(*args)
            res = fix_json(res, flags)
            entry["res"] = res
            # Log the result obtained.
            puts "DEBUG: Result obtained: #{struct_utils.stringify(res)}" if ENV['DEBUG']
            check_result(entry, args, res, struct_utils)
          rescue => err
            handle_error(entry, args, err, struct_utils)
          end
        end
      end

      runset = lambda do |testspec, testsubject|
        runsetflags.call(testspec, {}, testsubject)
      end

      { spec: spec, runset: runset, runsetflags: runsetflags, subject: subject, client: client }
    end
  end

  # Loads the test JSON file and extracts the spec for the given name.
  # Follows the pattern: alltests.primary?[name] || alltests[name] || alltests.
  def self.resolve_spec(name, testfile)
    full_path = File.expand_path(testfile, __dir__)
    all_tests = JSON.parse(File.read(full_path))
    if all_tests.key?("primary") && all_tests["primary"].key?(name)
      spec = all_tests["primary"][name]
    elsif all_tests.key?(name)
      spec = all_tests[name]
    else
      spec = all_tests
    end
    spec
  end

  # If the spec contains a DEF section with client definitions, resolve them.
  # For each defined client, obtain its test instance via client.test(options).
  def self.resolve_clients(client, spec, store, struct_utils)
    clients = {}
    if spec["DEF"] && spec["DEF"]["client"]
      spec["DEF"]["client"].each do |cn, cdef|
        copts = (cdef["test"] && cdef["test"]["options"]) || {}
        # If there is an injection method defined, apply it.
        if store.is_a?(Hash) && struct_utils.respond_to?(:inject)
          struct_utils.inject(copts, store)
        end
        clients[cn] = client.test(copts)
      end
    end
    clients
  end

  # Returns the subject under test.
  # In TS, resolveSubject returns container?.[name] (or the provided subject).
  def self.resolve_subject(name, container, subject = nil)
    if subject
      subject
    elsif container.respond_to?(name)
      container.send(name)
    else
      container[name]
    end
  end

  # Ensure flags is a hash and set "null" flag to true if not provided.
  def self.resolve_flags(flags)
    flags ||= {}
    flags["null"] = true unless flags.key?("null")
    flags
  end

  # If the entry's "out" field is nil and the flag "null" is true, substitute NULLMARK.
  def self.resolve_entry(entry, flags)
    entry["out"] = (entry["out"].nil? && flags["null"]) ? NULLMARK : entry["out"]
    entry
  end

  # Checks that the actual result matches the expected output.
  # Uses a deep equality check (via JSON round-trip) and may use a "match" clause.
  def self.check_result(entry, args, res, struct_utils)
    matched = false
    if entry.key?("match")
      result = { "in" => entry["in"], "args" => args, "out" => entry["res"], "ctx" => entry["ctx"] }
      match(entry["match"], result, struct_utils)
      matched = true
    end

    # Log expected and actual values before comparison.
    puts "DEBUG check_result: expected=#{struct_utils.stringify(entry['out'])} actual=#{struct_utils.stringify(res)}" if ENV['DEBUG']

    if entry["out"] == res
      return
    end

    if matched && (entry["out"] == NULLMARK || entry["out"].nil?)
      return
    end

    unless deep_equal?(res, entry["out"])
      raise "Mismatch: Expected #{struct_utils.stringify(entry['out'])} but got #{struct_utils.stringify(res)}"
    end
  end

  # In case of error during test execution, handle it.
  def self.handle_error(entry, args, err, struct_utils)
    entry["thrown"] = err
    if entry.key?("err")
      if entry["err"] === true || matchval(entry["err"], err.message, struct_utils)
        if entry.key?("match")
          match(entry["match"], { "in" => entry["in"], "args" => args, "out" => entry["res"], "ctx" => entry["ctx"], "err" => err }, struct_utils)
        end
        return
      end
      raise "ERROR MATCH: [#{struct_utils.stringify(entry['err'])}] <=> [#{err.message}]"
    else
      raise err
    end
  end

  # Resolves arguments for the test subject.
  # By default, it passes a clone of entry["in"].
  # When entry has no "in" key, pass struct UNDEF so typify etc. can return T_noval.
  # If entry["ctx"] or entry["args"] is provided, use that instead.
  # Also, if passing an object, inject client and utility.
  def self.resolve_args(entry, testpack, struct_utils)
    first = if entry.key?("in")
              struct_utils.clone(entry["in"])
            elsif struct_utils.const_defined?(:UNDEF, false)
              struct_utils.const_get(:UNDEF)
            else
              nil
            end
    args = [first]
    if entry.key?("ctx")
      args = [entry["ctx"]]
    elsif entry.key?("args")
      args = entry["args"]
    end

    if entry.key?("ctx") || entry.key?("args")
      first = args[0]
      if first.is_a?(Hash) && !first.nil?
        entry["ctx"] = struct_utils.clone(first)
        first["client"] = testpack[:client]
        first["utility"] = testpack[:utility]
        args[0] = first
      end
    end
    args
  end

  # Resolves the test pack for a test entry.
  # If the entry specifies a client override, use that client's utility and subject.
  def self.resolve_test_pack(name, entry, subject, client, clients)
    testpack = { client: client, subject: subject, utility: client.utility }
    if entry.key?("client")
      testpack[:client] = clients[entry["client"]]
      testpack[:utility] = testpack[:client].utility
      testpack[:subject] = resolve_subject(name, testpack[:utility])
    end
    testpack
  end

  # A simple recursive walk function that iterates over scalars in a structure.
  def self.walk(obj, path = [], &block)
    if obj.is_a?(Hash)
      obj.each do |k, v|
        new_path = path + [k]
        if v.is_a?(Hash) || v.is_a?(Array)
          walk(v, new_path, &block)
        else
          yield(k, v, obj, new_path)
        end
      end
    elsif obj.is_a?(Array)
      obj.each_with_index do |v, i|
        new_path = path + [i]
        if v.is_a?(Hash) || v.is_a?(Array)
          walk(v, new_path, &block)
        else
          yield(i, v, obj, new_path)
        end
      end
    end
  end

  # Compares scalar values along each path of the check structure against the base.
  def self.match(check, base, struct_utils)
    walk(check) do |_key, val, _parent, path|
      scalar = !(val.is_a?(Hash) || val.is_a?(Array))
      if scalar
        baseval = struct_utils.getpath(path, base)
        next if baseval == val
        next if val == UNDEFMARK && baseval.nil?
        unless matchval(val, baseval, struct_utils)
          raise "MATCH: #{path.join('.')} : [#{struct_utils.stringify(val)}] <=> [#{struct_utils.stringify(baseval)}]"
        end
      end
    end
  end

  # Returns true if check and base are considered matching.
  # For strings, it allows regular expression-like syntax.
  def self.matchval(check, base, struct_utils)
    pass = (check == base)
    unless pass
      if check.is_a?(String)
        basestr = struct_utils.stringify(base)
        if check =~ /^\/(.+)\/$/
          regex = Regexp.new($1)
          pass = regex.match?(basestr)
        else
          pass = basestr.downcase.include?(struct_utils.stringify(check).downcase)
        end
      elsif check.respond_to?(:call)
        pass = true
      end
    end
    pass
  end

  # Uses JSON round-trip to test deep equality.
  def self.deep_equal?(a, b)
    JSON.generate(a) == JSON.generate(b)
  end

  # Returns a deep copy of a value via JSON round-trip.
  def self.fix_json(val, flags)
    return flags["null"] ? NULLMARK : val if val.nil?
    JSON.parse(JSON.generate(val))
  end

  # Applies a null modifier: if a value is "__NULL__", it replaces it with nil.
  def self.null_modifier(val, key, parent)
    if val == "__NULL__"
      parent[key] = nil
    elsif val.is_a?(String)
      parent[key] = val.gsub("__NULL__", "null")
    end
  end
end
