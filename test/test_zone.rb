require 'init_test_env'

class TestZone < Minitest::Test
  def setup
    base_path = '/servers/localhost'
    @zone = Zone.new id: 'example.com',
      name: 'example.com',
      type: 'Zone',
      kind: 'Master',
      url: "#{base_path}/zones/example.com",
      dnssec: true

    @zones = [@zone]

    ActiveResource::HttpMock.respond_to do |mock|
      mock.get "#{base_path}/zones", Zone.headers, @zones.to_json
      mock.get @zone.url, Zone.headers, @zone.to_json
      mock.get "#{base_path}/zones/not_existent.com", Zone.headers, nil, 404
      mock.delete @zone.url, Zone.headers, nil, 204
    end
  end

  def test_all
    assert Zone.all
  end

  def test_get
    assert Zone.get('example.com')
    assert_raises(ActiveResource::ResourceNotFound) do
      Zone.find('not_existent.com')
    end
  end

  def test_delete
    assert Zone.find('example.com').destroy
  end

end

