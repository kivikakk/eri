# frozen_string_literal: true

require 'rtlil'

class TestRTLIL < Minitest::Test
  def test_roundtrip
    input = File.read(File.join(File.dirname(__FILE__), 'rtlil.il'))
    mods = RTLIL.parse(input)
    out = StringIO.open do |io|
      mods.each { |mod| mod.format(io:) }
      io.string
    end
    assert_equal input, out
  end
end
