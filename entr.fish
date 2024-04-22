#!/usr/bin/env fish

while sleep 1
    find . -name \*.zig | grep -v zig-cache | /opt/homebrew/bin/entr -cd zig build run
end
