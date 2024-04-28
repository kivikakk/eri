# frozen_string_literal: true

module HDL
  class Reg
    def initialize(mde, name, size, reset)
      @mde = mde
      @name = name
      @size = size
      @reset = reset
    end

    include HDL::Value

    attr_reader :size

    def to_s
      "Reg(#@name, #@size)"
    end

    def !
      HDL::Unop.new(:!, self)
    end

    def =~(rv)
      @mde.assign self, rv
    end
  end
end
