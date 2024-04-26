attribute \top 1
attribute \generator "eri"
module \top
  attribute \src "module print test"
  memory width 8 size 71 \rom_rd
  wire width 1 \clk
  wire width 1 inout 0 \led_0__io
  connect \i2c_bus__busy \led_0__o [0]
  attribute \src "module print test again"
  cell $dff $31
    parameter \WIDTH 1
    parameter \CLK_POLARITY 1
    connect \D $8
    connect \CLK \clk
    connect \Q \w_en
  end
  cell $memrd_v2 $70
    parameter \MEMID "\\storage"
    parameter \WIDTH 8
    parameter \ABITS 5
    connect \ADDR $signature__addr$18 [4:0]
    connect \ARST 1'0
  end
  process $30
    assign $8 [0] \w_en [0]
    switch \fsm_state [1:0]
      case 2'00
        assign $8 [0] 1'0
      case 2'01
      case 2'10
        switch \w_rdy [0]
          case 1'1
            assign $8 [0] 1'1
        end
      case 2'11
        assign $8 [0] 1'0
      case 2'-1
    end
    switch \rst [0]
      case 1'1
        assign $8 [0] { 4'0000 \read__value [15] }
      case
    end
  end
end
