# Smoke test for the Ruby test provider port. Prints summary stats that must
# match the canonical TS output documented in PROVIDER.

require_relative 'provider'

def main
  prov = TestProvider.load

  fns = prov.functions
  puts "functions: #{fns.join(', ')}"

  total = 0
  expect_kinds = Hash.new(0)
  input_kinds = Hash.new(0)
  fns.each do |fn|
    prov.entries(fn).each do |entry|
      total += 1
      expect_kinds[entry[:expect][:kind]] += 1
      input_kinds[entry[:input][:kind]] += 1
    end
  end

  puts "total entries: #{total}"
  puts "expect kinds: #{expect_kinds.map { |k, v| "#{k}=#{v}" }.join(', ')}"
  puts "input kinds: #{input_kinds.map { |k, v| "#{k}=#{v}" }.join(', ')}"

  e = prov.entries('getpath', 'basic')[0]
  puts "getpath/basic[0]: id=#{e[:id]}, doc=#{e[:doc]}, " \
       "input.kind=#{e[:input][:kind]}, " \
       "expect.kind=#{e[:expect][:kind]}, expect.value=#{e[:expect][:value]}"
end

main if __FILE__ == $PROGRAM_NAME
