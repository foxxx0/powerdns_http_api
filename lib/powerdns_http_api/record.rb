# coding: utf-8

module PowerdnsHttpApi

  class Record < Resource

    include Comparable


    # Representation of a SOA resource record.
    SOA = Struct.new(:raw, :mname, :rname, :serial, :refresh, :retry,
                     :expire, :negcache) do

      # @param rr [Record]
      def initialize(rr)
        if not rr.respond_to?(:type)
          raise ArgumentError, "must be a Record. '#{rr.class}' given."
        elsif not rr.soa?
          raise ArgumentError, "must be a SOA Record. '#{rr.type}' given."
        else
          super(rr.content, *rr.content.split)
        end
      end

    end


    schema do
      string(*%w(name type content))
      integer 'ttl'
      boolean 'disabled'
    end

    # Since the records are only available as part of the zone and
    # don't bring their own id, use the hexhash as id.
    alias :id :hexhash

    fixed_values type: %w(A AAAA AFSDB CERT CNAME DLV DNAME DNSKEY DS
      EUI48 EUI64 HINFO KEY LOC MINFO MX NAPTR NS NSEC NSEC3 NSEC3PARAM
      OPT PTR RKEY RP RRSIG SOA SSHFP SRV TLSA TXT)

    validates :name, presence: true,
      format: {with: /[^.]\z/, message: :no_trailing_dots}
    validates :ttl, presence: true,
      numericality: { only_integer: true, less_than: 2**32}
    validates :disabled, inclusion: {in: [true, false]}
    validate :name_is_absolute


    # Zone object that record belongs to.
    # 
    # @param zone [Zone]
    # @return [Zone]
    attr_accessor :zone


    # @return [void]
    def disable
      self.disabled = true
    end


    # @return [void]
    def enable
      self.disabled = false
    end


    # @param other [Record]
    # @return [Boolean]
    def ==(other)
      super(other) && attributes == other.attributes
    end


    # @return [Fixnum, nil]
    def priority
      content.split[-2][/\d+/] if mx? 
    end


    # @return [RRSet]
    def rrset
      RRSet.new self.name, self.type
    end


    # Check if two Records belong to the same rrset.
    #
    # @param other [Record]
    def same_rrset?(other)
      rrset == other.rrset
    end


    # @return [Array(String)]
    def labels
      name.split('.')
    end


    # @return [String]
    def shortname
      relative_name(self.name.to_s)
    end


    # @return [String]
    def shortcontent
      case self.type
      when 'MX' then relative_name(content.split.last)
      when 'CNAME' then relative_name(content)
      else content
      end
    end


    # @param shortnames [Boolean] whether to use short domain names 
    # @param namelength [Fixnum] minlength of name field
    # @return [String] BIND zone file line representation
    def to_zone_file_line(shortnames: false, namelength: 30)
      name, content = if shortnames
                        [shortname, shortcontent]
                      else
                        attributes.values_at(:name, :content)
                      end

      args = [name, ttl, type, priority, content]

      "%-#{namelength}s %5s IN %-6s %2s %s" % args
    end


    # @param content [String] new content
    # @param remote_ip [String] fallback content for A and AAAA records
    # @return [self]
    def update_content!(content, remote_ip)
      content ||= remote_ip if a? and remote_ip[/\./]
      content ||= remote_ip if aaaa? and remote_ip[/\:/]

      raise 'No content given' unless content

      attributes['content'] = content

      self.zone.update_records!

      self
    end


    # @param (see #update_content!)
    # @return [Boolean]
    def update_content(*args)
      update_content!(*args)
      true
    rescue RuntimeError, ActiveResource::Errors => e
      errors.add(:base, e.message)
      false
    end


    # @return [-1, 0, 1] if comparable
    # @return [nil] if not comparable
    def <=>(other)
      other.is_a?(self.class) ? compare(other) : super
    end


    # Before a Record is saved we need to make sure that the name
    # doesn't end with a '.' and set or add the zone name if it isn't
    # present yet. Also other values should be sanitized.
    #
    # @return [self]
    def sanitize_values!
      self.name.chomp!('.')

      append_zone_name! self.name
      append_zone_name! self.content if mx? or cname?

      if mx? and not priority
        content.insert(0, "#{self.try(:prio) || 10} ")
      end

      self.ttl = self.ttl.to_i
      self.disabled = !!self.disabled

      attributes.delete(:prio)

      self
    end


    protected

    # Compare Records to provide a sane order. We want SOA records first,
    # then NS, then MX and the rest ordered by its name.
    # This comparison is inteded to be used for ordering of resource
    # records for a single domain.
    #
    # @param other [Record]
    #
    # @return [-1, 0, 1]
    def compare(other)
      comparisons = %i(type content).inject({}) do |hash, attr| 
        hash.merge(attr => self.send(attr) <=> other.send(attr))
      end

      unless comparisons[:type].zero?
        %w(SOA NS).each do |rtype|
          case rtype
          when self.type  then return -1
          when other.type then return 1
          end
        end
      end

      comparisons[:name] =
        (self.labels - other.labels) <=> (other.labels - self.labels)

      %i(name type content).each do |attr|
        return comparisons[attr] unless comparisons[attr].zero?
      end

      return 0
    end


    private

    # @param record_name [String]
    # @return [String]
    def relative_name(record_name)
      relname = record_name.sub(/.?#{@zone.name}\.?$/,'')
        relname.blank? ? '@' : relname
    end


    # @param record_name [String]
    # @return [void]
    def append_zone_name!(string)
      if string.in? [nil, '', '@']
        string.replace(@zone.name)
      else
        string.sub!(/$(?<!#{@zone.name}|\.)/, ".#{@zone.name}")
      end
    end


    # @api private
    # validation method that checks if the record name is ending with
    # the zone name
    def name_is_absolute
      unless self.name[/#{@zone.name}$/]
        errors.add(:name, :not_absolute)
      end
    end

  end

end

