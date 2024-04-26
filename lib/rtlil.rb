# frozen_string_literal: true

require 'stringio'

module RTLIL
  def self.indent(io, indent)
    io.print(' ' * (indent * 2))
  end

  def self.attributes(io, indent, attributes)
    attributes.each { |attr| attr.format(io:, indent:) }
  end

  class Attribute
    def initialize(name, value)
      @name = name
      @value = value
    end

    def format(io:, indent: 0)
      RTLIL.indent(io, indent)
      io.puts "attribute #@name #{@value.inspect}"
    end
  end

  class Module
    def initialize(name, elements, attributes)
      @name = name
      @elements = elements
      @attributes = attributes
    end

    def format(io:)
      RTLIL.attributes(io, 0, @attributes)
      io.puts "module #@name"
      @elements.each do |element|
        element.format(io:, indent: 1)
      end
      io.puts 'end'
    end
  end

  class Memory
    def initialize(name, width, size, attributes)
      @name = name
      @width = width
      @size = size
      @attributes = attributes
    end

    def format(io:, indent:)
      RTLIL.attributes(io, indent, @attributes)
      RTLIL.indent(io, indent)
      io.puts "memory width #@width size #@size #@name"
      io.string
    end
  end

  class Wire
    def initialize(name, width, direction, index, attributes)
      @name = name
      @width = width
      @direction = direction
      @index = index
      @attributes = attributes
    end

    def format(io:, indent:)
      RTLIL.attributes(io, indent, @attributes)
      RTLIL.indent(io, indent)
      io.print "wire width #@width "
      io.print "#@direction #@index " if @direction
      io.puts @name
    end
  end

  class Connect
    def initialize(name, rvalue, attributes)
      @name = name
      @rvalue = rvalue
      @attributes = attributes
    end

    def format(io:, indent:)
      RTLIL.attributes(io, indent, @attributes)
      RTLIL.indent(io, indent)
      io.print "connect #@name "
      @rvalue.format(io:)
      io.puts
    end
  end

  class RValue
    def initialize(name, index)
      @name = name
      @index = index
    end

    def format(io:)
      io.print "#@name [#@index]"
    end
  end
end

require_relative 'rtlil/parser'
