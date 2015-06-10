require 'init_test_env'

class TestZone < Minitest::Test
  def setup
    @zones = [{}]
    base_path = '/servers/localhost'
    ActiveResource::HttpMock.respond_to do |mock|
      mock.get "#{base_path}/zones", Zone.headers, @zones.to_json
      mock.get "#{base_path}/zones/1", Zone.headers, @zones.first.to_json
    end
  end

  def test_all
    assert Zone.all
  end

  def test_get
    assert Zone.get(1)
  end

end
