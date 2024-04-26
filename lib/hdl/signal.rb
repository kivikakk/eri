# frozen_string_literal: true

module HDL
  class Signal
    include HDL::Value

    def initialize(size, reset: 0, name: nil)
      if name.nil?
        loc = caller_locations[0]
        line = File.readlines(loc.path)[loc.lineno - 1]
        name = begin
          # If it compiles on its own and matches, good chance it's fine.
          RubyVM::InstructionSequence.compile(line)
          line =~ %r{\A\s*(\w+)\s*=} or raise 'nope'
          $1
        rescue Exception
          raise "couldn't infer name for Signal"
        end
      end
      name.is_a?(String) or
        raise "Signal name #{name} isn't a String"
      size.is_a?(Integer) or
        raise "Signal size #{size} isn't an Integer"
      reset.is_a?(Integer) or
        raise "Signal reset #{reset} isn't an Integer"
      @name = name
      @size = size
      @reset = reset
    end

    attr_reader :size

    def to_s(loc: :rv)
      case loc
      when :lv
        "<Signal #{@name} (#{@size})>"
      else
        @name
      end
    end

    def eq(rv)
      HDL::Eq.new(self, rv)
    end
  end
end
