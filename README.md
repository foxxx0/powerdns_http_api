# PowerdnsHttpApi

Library for interaction with the experimental [PowerDNS HTTP API][1]. It is
built upon ActiveResource, although The API is only partially RESTful.
Records have no ID and are always considered as part of a [RRSet][2], which
has all records of same name and type.

[1]: https://doc.powerdns.com/md/httpapi/README/ 'PowerDNS Documentation'
[2]: https://doc.powerdns.com/md/httpapi/api_spec/#url-serversserver95idzoneszone95id

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'powerdns_http_api'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install powerdns_http_api

## Usage

```ruby
PowerdnsHttpApi::BASE_URL = 'http://ns1.example.com/servers/localhost'
PowerdnsHttpApi::API_KEY  = 'LookAtMeIamAnApiKey'
Zone.all # => #<ActiveResource::Collection:0x0000000255ff58...
zone = Zone.find 'example.com' # => #<PowerdnsHttpApi::Zone id: "example.com."...
zone.records # => [#<PowerdnsHttpApi::Record name: "www.example.com" ...>, ...]
```

## Contributing

1. Fork it ( https://github.com/aibor/powerdns_http_api/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
