# frozen_string_literal: true

module HDL
  class IO
    def initialize(mde, name, size, dir)
      @mde = mde
      @name = name
      @size = size
      @dir = dir
    end

    attr_reader :name, :size, :dir

    def to_s
      "IO(#@name, #@dir)"
    end

    def =~(rv)
      @mde.assign self, rv
    end
  end
end
