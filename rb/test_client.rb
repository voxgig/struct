require 'minitest/autorun'
require_relative 'voxgig_struct'
require_relative 'voxgig_runner'

# Path to the JSON test file (adjust as needed)
TEST_JSON_FILE = File.join(File.dirname(__FILE__), '..', 'build', 'test', 'test.json')

# Dummy client for testing: it must provide a utility method returning an object
# with a "struct" member (which is our VoxgigStruct module).
class DummyClient
  def utility
    require 'ostruct'
    OpenStruct.new(struct: VoxgigStruct)
  end

  def test(_options = {})
    self
  end
end

class TestClient < Minitest::Test
  def setup
    @client = DummyClient.new
    @runner = VoxgigRunner.make_runner(TEST_JSON_FILE, @client)
    @runpack = @runner.call('check')
    @spec = @runpack[:spec]
    @runset = @runpack[:runset]
    @subject = @runpack[:subject]
  end

  def test_client_check_basic
    @runset.call(@spec['basic'], @subject)
  end
end
