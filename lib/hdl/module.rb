# frozen_string_literal: true

require_relative '../identify'

module HDL
  def self.module(name: RTLIL.name(identify), &block)
    Module.new(name).from_dsl(&block)
  end

  class Module
    def initialize(name)
      @name = name
      @ios = [
        @clk = IO.new(self, "clk", 1, :in),
        @reset = IO.new(self, "reset", 1, :in),
      ]
      @regs = []
      @assigns = []
    end

    attr_reader :ios, :regs, :assigns
    attr_reader :clk, :reset

    def dump
      puts "=== module #{@name} ==="
      puts "#{@ios.length} io(s), #{@regs.length} reg(s)"
      @ios.each { |s| puts s }
      @regs.each { |s| puts s }
      puts
      puts "#{@assigns.length} assign(s)"
      @assigns.each { |s| puts s }
    end

    def dump_rtlil
      mod = RTLIL::Module.new(@name, [], [])
      # wire per IO
      @ios.each.with_index do |io, ix|
        mod.build!.wire(
          RTLIL.name(io.name),
          io.size,
          io.dir == :in ? 'input' : 'output',
          ix,
          [],
        )
      end
      # D and Q wires + DFF per reg
      intctr = 0
      @regs.each do |reg|
        # TODO: insert the reset here.
        d = mod.build!.wire("$#{intctr}", reg.size, nil, nil, [])
        intctr += 1
        q = mod.build!.wire("$#{intctr}", reg.size, nil, nil, [])
        intctr += 1
        cell = mod.build!.cell(
          '$dff',
          "$#{intctr}",
          [],
          [],
        )
        intctr += 1
        cell.build!.parameter('\\WIDTH', reg.size)
        cell.build!.parameter('\\CLK_POLARITY', 1)
        # XXX
        # TODO: better wire rvalue builders here
        cell.build!.connect('\\D', RTLIL::RValue::Wire.new(d.name, 0, reg.size - 1), [])
        cell.build!.connect('\\CLK', RTLIL::RValue::Wire.new("\\#{@clk.name}", 0), [])
        cell.build!.connect('\\Q', RTLIL::RValue::Wire.new(q.name), [])
      end
      # TODO: processes and connects to tie it all together
      # TODO: own class for generating RTLIL
      mod.format(io: $stdout)
    end

    def from_dsl(&block)
      ModuleDslEvaluator.new(self).instance_eval(&block)
      self
    end
  end

  class ModuleDslEvaluator
    def initialize(mod)
      @mod = mod
      @ctxs = []
    end

    # TODO: plain wire.

    def io(dir, size = 1, name: identify)
      dir == :in || dir == :out or raise 'dir must be :in or :out'
      IO.new(self, name, size, dir).tap { |io| @mod.ios << io }
    end

    def reg(size = 1, name: identify, reset: 0)
      Reg.new(self, name, size, reset).tap { |r| @mod.regs << r }
    end

    def assign(reg, rv)
      @mod.assigns << Assign.new(@ctxs.dup, reg, rv)
      nil
    end

    def iff(cond, &block)
      @ctxs << cond
      begin
        block.call
      ensure
        @ctxs.pop
      end
      nil
    end
  end
end
