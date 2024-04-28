# frozen_string_literal: true

def identify(ends: ['', ' end', ' }'])
  loc = caller_locations[1]
  line = File.readlines(loc.path)[loc.lineno - 1]

  ends.any? do |e|
    RubyVM::InstructionSequence.compile(line + e)
  rescue Exception
    # nope
  end or return nil
  line =~ %r{\A\s*(\w+)\s*=} or return nil
  $1
end
