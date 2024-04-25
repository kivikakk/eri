# frozen_string_literal: true

module HDL
  class Stmt; end

  class Eq < HDL::Stmt
    def initialize(lv, rv)
      super()

      lv.is_a?(HDL::Signal) or
        raise "Eq lv #{lv} isn't a Signal"
      @lv = lv
      @rv = HDL::Value.from(rv) or
        raise "Eq rv #{rv} not Value"
    end

    def to_s
      "#{@lv.to_s(loc: :lv)} = #@rv"
    end
  end
end
