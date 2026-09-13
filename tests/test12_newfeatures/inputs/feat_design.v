// Structural Netlist for Test 12: N4 / W2 / P7 / G8 non-regression.
// Non-ANSI port style. Uses one flop (DFQD0, sync pin CP) and a high-fanout
// buffer chain so the new features can be exercised:
//   - P7 forward-to-sync trace (-from only) reaches the flop CP.
//   - G8 high-fanout net count once build_net_conn + set_max_fanout run.
//   - P7 -limit caps the reported sync endpoints (here only one sync sink).
//   - N4/W2 verified on the saved/restored db and after a placement move.
module feat_top ( clk, d, q, hi_in, o0, o1, o2, o3 );
  input  clk;
  input  d;
  output q;
  input  hi_in;
  output o0;
  output o1;
  output o2;
  output o3;
  wire q_net;
  wire hi_net;
  DFQD0 feat_ff ( .D(d), .CP(clk), .Q(q_net) );
  assign q = q_net;
  // One driver (hi_net) feeding 4 receivers: high-fanout above a threshold of 2.
  assign hi_net = hi_in;
  BUFFD1 b0 ( .I(hi_net), .Z(o0) );
  BUFFD1 b1 ( .I(hi_net), .Z(o1) );
  BUFFD1 b2 ( .I(hi_net), .Z(o2) );
  BUFFD1 b3 ( .I(hi_net), .Z(o3) );
endmodule
