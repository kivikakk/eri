# frozen_string_literal: true

require 'stringio'

module HDL
  class Module
    def initialize(name)
      @name = name
      @combs = []
      @syncs = []

      @comb = HDL::DomainBuilder.new(self, :@combs)
      @sync = HDL::DomainBuilder.new(self, :@syncs)
    end

    attr_reader :comb, :sync

    def dump
      puts "=== module #{@name} ==="
      puts "#{@combs.length} comb(s)"
      @combs.each { |s| puts s }
      puts "#{@syncs.length} sync(s)"
      @syncs.each { |s| puts s }
    end
  end

  class DomainBuilder
    def initialize(m, attr)
      @m = m
      @attr = attr
    end

    def <<(stmt)
      stmt.is_a?(HDL::Stmt) or
        raise "Domain stmt #{stmt} isn't a Stmt"
      @m.instance_variable_get(@attr) << stmt
    end
  end

  class Resource
    def self.find(name)
      new(name)
    end

    def initialize(name)
      @name = name
      @o = HDL::Signal.new("#@name.o", 1)
    end

    attr_reader :o
  end
end
