# frozen_string_literal: true

require 'parslet'

module RTLIL
  class Parser < Parslet::Parser
    rule(:space) { str(' ') }
    rule(:nl) { str("\n") }
    rule(:word) { match['$\\\\'] >> match['$\\\\a-zA-Z0-9_'].repeat(1) }

    rule(:number) { match['0-9'].repeat(1).as(:number) }
    rule(:string) { str('"') >> match('[^"]').repeat.as(:string_body) >> str('"') }
    rule(:value) { number | string }

    rule(:rvalue_wire) do
      word.as(:name) >>
        begin
          space >> str('[') >>
          (match['0-9'].repeat(1).as(:upper) >> str(':')).maybe >>
          match['0-9'].repeat(1).as(:index) >>
          str(']')
        end.maybe
    end
    rule(:rvalue_bv) do
      match['0-9'].repeat(1).as(:size) >> str("'") >> match['01'].repeat(1).as(:bits)
    end
    rule(:rvalue) do
      rvalue_wire.as(:wire) |
        rvalue_bv.as(:bv)
    end

    rule(:attribute) do
      space.repeat >> str('attribute') >> space >>
        word.as(:name) >> space >>
        value.as(:value) >> nl
    end
    rule(:parameter) do
      space.repeat >> str('parameter') >> space >>
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

    rule(:cell_start) do
      space.repeat >> str('cell') >> space >>
        word.as(:kind) >> space >> word.as(:name) >> nl
    end
    rule(:cell_entry) do
      parameter.as(:parameter) |
        connect.as(:connect)
    end
    rule(:cell) do
      cell_start >>
        cell_entry.repeat >>
        space.repeat >> str('end') >> nl
    end

    rule(:assign) do
      space.repeat >> str('assign') >> space >>
        rvalue_wire.as(:signal) >> space >>
        rvalue.as(:rvalue) >> nl
    end

    rule(:process_start) { space.repeat >> str('process') >> space >> word.as(:name) >> nl }
    rule(:process_entry) do
      assign.as(:assign)
    end
    rule(:process) do
      process_start >>
        process_entry.repeat >>
        space.repeat >> str('end') >> nl
    end

    rule(:mod_start) { str('module') >> space >> word.as(:name) >> nl }
    rule(:mod_entry) do
      attribute.as(:attribute) |
        memory.as(:memory) |
        wire.as(:wire) |
        connect.as(:connect) |
        cell.as(:cell) |
        process.as(:process)
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
        string_body.to_s.gsub(%r{\\(.)}, '\1')
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

  def Parameter.from(data)
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
      elsif (data = token[:cell])
        elements << RTLIL::Cell.from(data, attrs.slice!(..-1))
      elsif (data = token[:process])
        elements << RTLIL::Process.from(data, attrs.slice!(..-1))
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
    case data
    in wire: {name:}
      index = data[:wire][:index]&.to_i
      upper = data[:wire][:upper]&.to_i
      RValue::Wire.new(name, index, upper)
    in bv: {size:, bits:}
      bits.length == size.to_i or
        raise "bitvector bits don't match defined size"
      RValue::Bitvector.new(bits.to_s.chars.map(&:to_i))
    end
  end

  def Cell.from(data, attributes)
    data => [{kind:, name:}, *rest]
    attrs = []
    elements = []

    rest.each do |token|
      if (data = token[:attribute])
        attrs << RTLIL::Attribute.from(data)
      elsif (data = token[:parameter])
        raise 'unexpected attribute for parameter in cell' if attrs.any?

        elements << RTLIL::Parameter.from(data)
      elsif (data = token[:connect])
        elements << RTLIL::Connect.from(data, attrs.slice!(..-1))
      else
        raise "unknown cell-level token: #{token.inspect}"
      end
    end

    raise 'leftover attributes in cell' if attrs.any?

    new(kind, name, elements, attributes)
  end

  def Process.from(data, attributes)
    data => [{name:}, *rest]
    attrs = []
    elements = []

    rest.each do |token|
      if (data = token[:assign])
        elements << RTLIL::Assign.from(data)
      else
        raise "unknown process-level token: #{token.inspect}"
      end
    end

    raise 'leftover attributes in process' if attrs.any?

    new(name, elements, attributes)
  end

  def Assign.from(data)
    data => {signal:, rvalue:}
    signal => {name:}
    index = signal[:index]&.to_i
    upper = signal[:upper]&.to_i

    new(RValue::Wire.new(name, index, upper), RValue.from(rvalue))
  end
end
