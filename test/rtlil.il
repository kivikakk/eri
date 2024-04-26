attribute \top 1
attribute \generator "eri"
module \top
  attribute \src "module print test"
  memory width 8 size 71 \rom_rd
  wire width 1 \clk
  wire width 1 inout 0 \led_0__io
  connect \i2c_bus__busy \led_0__o [0]
end
