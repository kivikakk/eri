#!/usr/bin/env fish

while sleep 0.5
    begin
        echo eri
        find lib -name \*.rb
    end | /opt/homebrew/bin/entr -cd ./eri
end
