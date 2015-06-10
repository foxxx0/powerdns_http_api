# coding: utf-8

require 'set'


module PowerdnsHttpApi

  # Represents PowerDNS Zone objects.

  class Zone < Resource

    schema do
      string(*%w(name kind soa_edit_api soa_edit dnssec account))
      integer(*%w(serial notified_serial last_check))
      boolean(*%(dnssec))
    end

    has_many :records, class_name: 'PowerdnsHttpApi::Record'
    has_many :cryptokeys, class_name: 'PowerdnsHttpApi::Cryptokey'

    soa_edits = %w(INCREMENT-WEEKS INCEPTION-EPOCH INCEPTION-INCREMENT
                   INCEPTION INCEPTION-WEEK EPOCH) + [nil, '']

    fixed_values kind: %w(Master Slave Native),
      soa_edit: soa_edits

    before_save :save_zone_details

    validates :name, presence: true,
      format: {with: /[^.]\z/, message: :no_trailing_dots}


    # If no TTL is provides, use this as the default.
    DEFAULT_TTL = 86400


    # @param nameserver [Array(String)] List of namserver IP addresses
    #   for the zone.
    attr_writer :nameservers


    # @param default_ttl [Fixnum] Set the default ttl for this zone.
    attr_writer :default_ttl


    # @api private
    def initialize(*args)
      super
      if self.attributes.keys.include?('records')
        records.each { |r| r.zone = self }
      else
        attributes[:records] ||= []
      end
    end


    # Find a zone by its {#hexhash} value, which is used as id.
    def find_record(id)
      self.records.find { |r| r.hexhash == id }
    end


    # If records have changed, it builds the relevant rrsets and submits
    # them to the server. If there are errors found, exceptions are
    # thrown.
    #
    # @return [self]
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


    # Like {#update_records!}, but doesn't throw exceptions. Instead,
    # an error is added to the object.
    #
    # @return [Boolean] if the update was successful
    def update_records
      update_records!
      true
    rescue ActiveResource::Errors => e
      self.errors.add(:records, e.message)
      false
    end


    # Return the default ttl used for this zone.
    #
    # @return [Fixnum]
    def default_ttl
      @default_ttl || DEFAULT_TTL
    end


    # @return [Array(RRSet)] List of all rrsets the zone has.
    def rrsets
      self.records.inject(Set.new) do |rrsets, record|
        rrset = record.rrset
        rrset.records = self.records.select { |r| r.same_rrset? record }
        rrsets << rrset
      end.to_a
    end


    # @return [Array(RRSet)] List of all rrsets that have changed.
    def changed_rrsets
      (rrsets - remote.rrsets) + remote.rrsets.select do |rr|
        unless rrsets.find { |r| r.head == rr.head }
          rr.records = []
          rr.changetype = 'DELETE'
        end
      end
    end


    # @return [Zone] new Zone object with the state of the object on
    #   the server.
    def remote
      @remote ||= self.class.find(self.id)
    end


    # @return [Record] the SOA resource record for the zone.
    def soa
      self.records.find(&:soa?)
    end


    # @return [Array(Record)] List of all NS resource records for the
    #   zone.
    def ns
      self.records.select(&:ns?)
    end

    
    # @return [Array(String)] List of namserver IP addresses for the
    #   zone.
    def nameservers
      ns.map(&:content)
    end


    # @param nameservers [Array(String)] List of namserver IP addresses
    #   for the zone.
    #
    # @return [self]
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


    # If the SOA resource record of the zone has the diabled flag set,
    # no requests for the zone are answered at all. Thus it is
    # considered disabled.
    #
    # @return [Boolean]
    def disabled?
      !!(self.soa && self.soa.disabled)
    end


    # Enables the zone by removing the disabled flag on the SOA resource
    # record.
    #
    # @return [self]
    def enable
      soa.enable
      update_records
    end


    # Disables the zone by setting the disabled flag on the SOA resource
    # record.
    #
    # @return [self]
    def disable
      soa.disable
      update_records
    end


    # Not supported yet
    #def secure_zone
    #  update_attributes dnssec: true
    #end


    # Not supported yet
    #def insecure_zone
    #  update_attributes dnssec: false
    #end


    # @return [Array(String)] List of DS Keys for the zone, if DNSSEC
    #   is enabled.
    def dskeys
      ksk = cryptokeys.find(&:ksk?)
      ksk ? ksk.ds : []
    end


    # In case the zone is of type 'Master', notify the slaves to
    # retrieve the zone.
    def notify
      put(:notify)
    end


    # In case the zone is of type 'Slave', invoke an AXFR action and
    # retrieve the zone from the master.
    def axfr
      put(:'axfr-retrieve')
    end


    # Create a BIND style zone file representation of the zone.
    #
    # @param kwargs [Boolean] :shortnames Use relative names instead of
    #   absolute names.
    #
    # @return [String]
    def to_zone_file(shortnames: false)
      max = records.map do |record|
        (shortnames ? record.shortname : record.name).length
      end.max

      records.sort.map do |record|
        record.to_zone_file_line(shortnames: shortnames, namelength: max)
      end
    end


    # @return [String]
    def inspect
      attrs = attributes.map { |k, v| "#{k}: #{v.inspect}" }
      "#<#{self.class} #{attrs.join(', ')}>"
    end

  end

end

