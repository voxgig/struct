require 'minitest/autorun'
require 'json'
require_relative 'voxgig_struct'

# Discovery test: pathological regex inputs run against the port's re_* API.
# Goal is to surface failures across ports, not to assert behaviour.
# Panel is the same in every port (see REGEX.md).

def record(label, &block)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  begin
    r = block.call
    outcome = "OK | #{JSON.generate(r)}"
  rescue StandardError => e
    outcome = "ERR | #{e.class.name}: #{e.message}"
  end
  ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0
  printf("[regex-discovery] %s | %.2fms | %s\n", label, ms, outcome)
end

class PathologicalRegexTest < Minitest::Test
  def test_panel
    a22 = 'a' * 22
    nest40 = "#{'(' * 40}a#{')' * 40}"

    record('P1_redos_nested_plus')      { VoxgigStruct.re_test('^(a+)+$', "#{a22}!") }
    record('P2_redos_alt_overlap')      { VoxgigStruct.re_test('^(a|aa)+$', "#{a22}!") }
    record('P3_empty_repeat_replace')   { VoxgigStruct.re_replace('a*', 'abc', 'X') }
    record('P4_unicode_replace_dot')    { VoxgigStruct.re_replace('\\.', 'café.au.lait', '/') }
    record('P5_unicode_find_codepoint') { VoxgigStruct.re_find('é', 'café au lait') }
    record('P6_deep_nesting_compile')   { VoxgigStruct.re_test(nest40, 'a') }
    record('P7_big_bounded_quantifier') { VoxgigStruct.re_test('^a{0,10000}b$', "#{'a' * 10}b") }
    record('P8_invalid_pattern')        { VoxgigStruct.re_compile('[abc') }
    record('P9_backref_re2_forbidden')  { VoxgigStruct.re_test('^(a+)\\1$', 'aaaa') }
    record('P10_find_all_zero_width')   { VoxgigStruct.re_find_all('a*', 'bbb') }
  end
end
