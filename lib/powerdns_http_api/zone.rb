# coding: utf-8

require 'set'


module PowerdnsHttpApi

  class Zone < Resource

    DEFAULT_TTL = 86400

    attr_accessor :nameservers

    attr_writer :default_ttl


    schema do
      string *%w(name kind soa_edit_api soa_edit dnssec account)
      integer *%w(serial notified_serial last_check)
      boolean *%(dnssec)
    end


    has_many :records, class_name: 'PowerdnsHttpApi::Record'
    has_many :cryptokeys, class_name: 'PowerdnsHttpApi::Cryptokey'


    soa_edits = %w(INCREMENT-WEEKS INCEPTION-EPOCH INCEPTION-INCREMENT
                   INCEPTION INCEPTION-WEEK EPOCH) + [nil, '']

    fixed_values kind: %w(Master Slave Native),
      soa_edit: soa_edits,
      soa_edit_api: soa_edits


    before_save :save_zone_details


    validates :name, presence: true,
      format: {with: /[^.]\z/, message: :no_trailing_dots}


    def initialize(*args)
      super
      if self.attributes.keys.include?('records')
        records.each { |r| r.zone = self }
      else
        attributes[:records] ||= []
      end
    end


    def find_record(id)
      self.records.find { |r| r.hexhash == id }
    end


    def update_records!
      changes = changed_rrsets

      return unless changes.any?

      unless changes.all?(&:valid?)
        record_errors = changes.inject({}) do |hash, rs|
          rs.records.each { |r| hash[r.id] = r.errors.messages }
          hash
        end
        errors.add(:records, record_errors)
        return false
      end

      self.class.connection.patch self.url,
        {rrsets: changes}.to_json,
        self.class.headers

      @remote = nil

      self
    end


    def update_records
      update_records!
      true
    rescue ActiveResource::Errors => e
      self.errors.add(:records, e.message)
      false
    end


    def default_ttl
      @default_ttl || DEFAULT_TTL
    end


    def rrsets
      self.records.inject(Set.new) do |rrsets, record|
        rrset = record.rrset
        rrset.records = self.records.select { |r| r.same_rrset? record }
        rrsets << rrset
      end
    end


    def changed_rrsets
      (rrsets - remote.rrsets) + remote.rrsets.select do |rr|
        unless rrsets.find { |r| r.head == rr.head }
          rr.records = []
          rr.changetype = 'DELETE'
        end
      end
    end


    def remote
      @remote ||= self.class.find(self.id)
    end


    def soa
      self.records.find(&:soa?)
    end


    def ns
      self.records.select(&:ns?)
    end


    def nameservers
      ns.map(&:content)
    end


    def replace_nameservers(nameservers = [])
      unless nameservers.is_a?(Array)
        raise ArgumentError, "not an Array: #{nameservers.class}"
      end

      nameservers.compact!

      unless nameservers.all? { |ns| ns.is_a?(String) }
        raise ArgumentError, 'not all elements are Strings'
      end

      self.records.reject!(&:ns?)
      self.records += nameservers.map do |nameserver|
        Record.new name: self.name, type: 'NS', ttl: default_ttl,
          disabled: false, content: nameserver
      end

      self
    end


    def disabled?
      !!(self.soa && self.soa.disabled)
    end


    def enable
      soa.enable
      update_records
    end


    def disable
      soa.disable
      update_records
    end


    def secure_zone
      update_attributes dnssec: true
    end


    def insecure_zone
      update_attributes dnssec: false
    end


    def dskeys
      ksk = cryptokeys.find &:ksk?
      ksk ? ksk.ds : []
    end


    def notify
      put(:notify)
    end


    def axfr
      put(:'axfr-retrieve')
    end


    def to_zone_file(shortnames: false)
      max = records.map do |record|
        (shortnames ? record.shortname : record.name).length
      end.max

      records.sort.map do |record|
        record.to_zone_file_line(shortnames: shortnames, namelength: max)
      end
    end


    def inspect
      attrs = attributes.map { |k, v| "#{k}: #{v.inspect}" }
      "#<#{self.class} #{attrs.join(', ')}>"
    end

  end

end

