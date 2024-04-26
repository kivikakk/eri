# frozen_string_literal: true

require 'parslet'

module RTLIL
  class Parser < Parslet::Parser
    rule(:space) { str(' ') }
    rule(:nl) { str("\n") }
    rule(:word) { match['$\\\\'].maybe >> match['a-zA-Z0-9_'].repeat(1) }

    rule(:number) { match['0-9'].repeat(1).as(:number) }
    rule(:string) { str('"') >> match('[^"]').repeat.as(:string_body) >> str('"') }
    rule(:value) { number | string }

    rule(:rvalue) do
      word.as(:name) >> space >> str('[') >> match['0-9'].repeat(1).as(:index) >> str(']')
    end

    rule(:attribute) do
      space.repeat >> str('attribute') >> space >>
        word.as(:name) >> space >>
        value.as(:value) >> nl
    end
    rule(:memory) do
      space.repeat >> str('memory') >> space >>
        str('width') >> space >> number.as(:width) >> space >>
        str('size') >> space >> number.as(:size) >> space >>
        word.as(:name) >> nl
    end
    rule(:wire) do
      space.repeat >> str('wire') >> space >>
        str('width') >> space >> number.as(:width) >> space >>
        (
          (str('inout') | str('input') | str('output')).as(:direction) >> space >>
          number.as(:index) >> space
        ).maybe >>
        word.as(:name) >> nl
    end
    rule(:connect) do
      space.repeat >> str('connect') >> space >>
        word.as(:name) >> space >>
        rvalue.as(:rvalue) >> nl
    end

    rule(:mod_start) { str('module') >> space >> word.as(:name) >> nl }
    rule(:mod_entry) do
      attribute.as(:attribute) |
        memory.as(:memory) |
        wire.as(:wire) |
        connect.as(:connect)
    end
    rule(:mod) { mod_start >> mod_entry.repeat >> str('end') >> nl }

    rule(:doc) { (attribute.as(:attribute) | mod.as(:module)).repeat }

    root(:doc)

    def self.value(data, assert = nil)
      if (number = data[:number])
        assert.nil? || assert == :number or
          raise "asserted #{assert.inspect}: #{data.inspect}"
        number.to_i
      elsif (string_body = data[:string_body])
        assert.nil? || assert == :string or
          raise "asserted #{assert.inspect}: #{data.inspect}"
        string_body.to_s
      else
        raise "unknown value: #{data.inspect}"
      end
    end

    def self.value?(data, assert = nil)
      data.nil? and return nil
      RTLIL::Parser.value(data, assert)
    end
  end

  def self.parse(input)
    attrs = []
    mods = []

    RTLIL::Parser.new.parse(input).each do |token|
      if (data = token[:attribute])
        attrs << RTLIL::Attribute.from(data)
      elsif (data = token[:module])
        mods << RTLIL::Module.from(data, attrs.slice!(..-1))
      else
        raise "unknown top-level token: #{token.inspect}"
      end
    end

    raise 'leftover attributes at top-level' if attrs.any?

    mods
  end

  def Attribute.from(data)
    data => {name:, value:}
    new(name, RTLIL::Parser.value(value))
  end

  def Module.from(data, attributes)
    data => [{name:}, *rest]
    attrs = []
    elements = []

    rest.each do |token|
      if (data = token[:attribute])
        attrs << RTLIL::Attribute.from(data)
      elsif (data = token[:memory])
        elements << RTLIL::Memory.from(data, attrs.slice!(..-1))
      elsif (data = token[:wire])
        elements << RTLIL::Wire.from(data, attrs.slice!(..-1))
      elsif (data = token[:connect])
        elements << RTLIL::Connect.from(data, attrs.slice!(..-1))
      else
        raise "unknown module-level token: #{token.inspect}"
      end
    end

    raise 'leftover attributes in module' if attrs.any?

    new(name, elements, attributes)
  end

  def Memory.from(data, attributes)
    data => {width:, size:, name:}
    new(name, RTLIL::Parser.value(width, :number), RTLIL::Parser.value(size, :number), attributes)
  end

  def Wire.from(data, attributes)
    data => {name:, width:}
    new(
      name,
      RTLIL::Parser.value(width, :number),
      data[:direction],
      RTLIL::Parser.value?(data[:index], :number),
      attributes,
    )
  end

  def Connect.from(data, attributes)
    data => {name:, rvalue:}
    new(name, RTLIL::RValue.from(rvalue), attributes)
  end

  def RValue.from(data)
    data => {name:, index:}
    new(name, index.to_i)
  end
end
