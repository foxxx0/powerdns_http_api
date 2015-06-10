# coding: utf-8

module PowerdnsHttpApi

  VERSION = '0.0.1'

  BASE_URL = 'http://not.working.example.com/servers/localhost'

  API_KEY = 'NotTheRightKey'


  autoload :Resource,     'powerdns_http_api/resource'
  autoload :Record,       'powerdns_http_api/record'
  autoload :Zone,         'powerdns_http_api/zone'
  autoload :Cryptokey,    'powerdns_http_api/cryptokey'
  autoload :RRSet,        'powerdns_http_api/rrset'

end

