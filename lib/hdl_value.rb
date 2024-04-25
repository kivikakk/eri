# frozen_string_literal: true

module HDL
  module Value
    def self.from(v)
      case v
      when HDL::Value
        v
      when Integer
        HDL::Constant.new(v)
      else
        nil
      end
    end

    def +(other)
      HDL::Binop.new(:+, self, other)
    end

    def [](ix)
      HDL::Index.new(self, ix)
    end
  end

  class Constant
    include HDL::Value

    def initialize(c, size: nil)
      c.is_a?(Integer) or
        raise "Constant #{c} isn't an Integer"
      if size.nil?
        size = Math.log2(c + 1).ceil
      else
        size.is_a?(Integer) && size.positive? or
          raise "Constant size #{size} isn't Integer (or is <= 0)"
      end

      @c = c
      @size = size
    end

    def to_s
      "#@size'x#{@c.to_s(16)}"
    end
  end
end
