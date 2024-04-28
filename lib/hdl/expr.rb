# frozen_string_literal: true

module HDL
  class Expr
    include HDL::Value
  end

  class Unop < HDL::Expr
    def initialize(kind, operand)
      super()

      %i[!].include?(kind) or
        raise "Unop kind #{kind} isn't :!"
      @kind = kind
      @operand = HDL::Value.from(operand) or
        raise "Unop operand #{operand} not Value"
    end

    def to_s
      "(#@kind #@operand)"
    end
  end

  class Binop < HDL::Expr
    def initialize(kind, lhs, rhs)
      super()

      %i[+ ==].include?(kind) or
        raise "Binop kind #{kind} isn't :+ or :=="
      @kind = kind
      @lhs = HDL::Value.from(lhs) or
        raise "Binop lhs #{lhs} not Value"
      @rhs = HDL::Value.from(rhs) or
        raise "Binop rhs #{rhs} not Value"
    end

    def to_s
      "(#@lhs #@kind #@rhs)"
    end
  end

  class Index < HDL::Expr
    def initialize(expr, ix)
      super()

      ix.is_a?(Integer) or
        raise "Index ix #{ix} not Integer"
      @e = HDL::Value.from(expr) or
        raise "Index expr #{expr} not Value"
      @ix = if ix >= 0
              ix
            else
              @e.size + ix
            end
    end

    def to_s
      "#@e[#@ix]"
    end
  end
end
