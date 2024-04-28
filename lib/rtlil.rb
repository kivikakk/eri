# frozen_string_literal: true

require 'stringio'

module RTLIL
  def self.indent(io, indent)
    io.print(' ' * (indent * 2))
  end

  def self.attributes(io, indent, attributes)
    attributes.each { |attr| attr.format(io:, indent:) }
  end

  def self.name(name)
    "\\#{name[0].downcase}#{name[1..].gsub(/A-Z/) { "_#{$_.downcase}" }}"
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

  class Parameter
    def initialize(name, value)
      @name = name
      @value = value
    end

    def format(io:, indent: 0)
      RTLIL.indent(io, indent)
      io.puts "parameter #@name #{@value.inspect}"
    end
  end

  class Container
    class Builder
      def initialize(container)
        @container = container
      end

      %w[Wire Cell Parameter Connect].each do |kind|
        define_method(kind.downcase) do |*args|
          elem = RTLIL.const_get(kind).new(*args)
          @container.elements << elem
          elem
        end
      end
    end

    def initialize(type, elements, attributes)
      @type = type
      @elements = elements
      @attributes = attributes
    end

    attr_reader :elements

    def format_open(io:)
      raise NotImplementedError
    end

    def format(io:, indent: 0)
      RTLIL.attributes(io, indent, @attributes)
      RTLIL.indent(io, indent)
      format_open(io:)
      @elements.each do |element|
        element.format(io:, indent: indent + 1)
      end
      RTLIL.indent(io, indent)
      io.puts 'end'
    end

    def build!
      @build ||= Builder.new(self)
    end
  end

  class Module < Container
    def initialize(name, *args)
      super('module', *args)
      @name = name
    end

    def format_open(io:)
      io.puts "module #@name"
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

    attr_reader :name

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

  module RValue
    class Wire
      def initialize(name, index = nil, upper = nil)
        @name = name
        @index = index
        @upper = upper || index
      end

      def format(io:)
        io.print @name.to_s
        if @index
          io.print ' ['
          io.print "#@upper:" if @upper != @index
          io.print "#@index]"
        end
      end
    end

    class Bitvector
      def initialize(bits)
        @bits = bits
      end

      def format(io:)
        io.print "#{@bits.count}'#{@bits.join}"
      end
    end
  end

  class Cell < Container
    def initialize(kind, name, *args)
      super('cell', *args)
      @kind = kind
      @name = name
    end

    def format_open(io:)
      io.puts "cell #@kind #@name"
    end
  end

  class Process < Container
    def initialize(name, *args)
      super('process', *args)
      @name = name
    end

    def format_open(io:)
      io.puts "process #@name"
    end
  end

  class Assign
    def initialize(signal, rvalue)
      @signal = signal
      @rvalue = rvalue
    end

    def format(io:, indent:)
      RTLIL.indent(io, indent)
      io.print 'assign '
      @signal.format(io:)
      io.print ' '
      @rvalue.format(io:)
      io.puts
    end
  end
end

require_relative 'rtlil/parser'
