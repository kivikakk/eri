# frozen_string_literal: true

require 'stringio'

module HDL
  class Assign
    def initialize(ctxs, reg, rv)
      @ctxs = ctxs
      @reg = reg
      @rv = rv
    end

    def to_s
      StringIO.open do |io|
        io.print "Assign(#@reg =~ #@rv"
        @ctxs.each do |ctx|
          io.print " | #{ctx}"
        end
        io.print ')'
        io.string
      end
    end
  end
end

require_relative 'hdl/module'
require_relative 'hdl/value'
require_relative 'hdl/reg'
require_relative 'hdl/io'
require_relative 'hdl/expr'
