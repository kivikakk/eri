# frozen_string_literal: true

module HDL
  class Signal
    include HDL::Value

    def initialize(name, size)
      size.is_a?(Integer) or
        raise "Signal size #{size} isn't an integer"
      @name = name
      @size = size
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
