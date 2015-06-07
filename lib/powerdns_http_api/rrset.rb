# coding: utf-8

class PowerdnsHttpApi::RRSet

  attr_accessor :name, :type, :changetype, :records


  def initialize(*args)
    @name, @type, @changetype, @records = *args
    @changetype ||= 'REPLACE'
    @records    ||= []
  end


  def head
    {name: self.name, type: self.type}
  end


  def valid?
    self.records.none? do |record|
      record.respond_to?(:valid) and not record.valid?
    end
  end

end

