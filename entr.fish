#!/usr/bin/env fish

if test (count $argv) -eq 0
  set cmd ./eri
else
  set cmd $argv
end

while sleep 0.5
    begin
        echo eri
        find lib -name \*.rb
        find test
    end | /opt/homebrew/bin/entr -cd $cmd
end
