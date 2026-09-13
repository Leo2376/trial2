// Structural Netlist for Test 13: E5 / P8 / P7-cycle / H2 non-regression.
// Non-ANSI port style. Combines:
//   - one flop (DFQD0, sync CP) for forward-to-sync tracing,
//   - a high-fanout buffer chain (one driver, 4 receivers),
//   - an inverter ring (two INVD1 feeding each other) so the forward trace
//     prunes a cyclic back-edge (P7 cycle guard),
//   - a hierarchical submodule (sub) with an input and an output port so
//     report_path can be checked for port-direction-aware hierarchy crossing
//     (P8).
module e5p8_top ( clk, d, q, hi_in, o0, o1, o2, o3, ring_in, ring_out, sub_in, sub_out );
  input  clk;
  input  d;
  output q;
  input  hi_in;
  output o0;
  output o1;
  output o2;
  output o3;
  input  ring_in;
  output ring_out;
  input  sub_in;
  output sub_out;

  wire q_net;
  wire hi_net;
  wire ring_a;
  wire ring_b;
  wire sub_out_net;

  DFQD0 e5_ff ( .D(d), .CP(clk), .Q(q_net) );
  assign q = q_net;

  // High-fanout: hi_net (1 driver) -> 4 receivers.
  assign hi_net = hi_in;
  BUFFD1 b0 ( .I(hi_net), .Z(o0) );
  BUFFD1 b1 ( .I(hi_net), .Z(o1) );
  BUFFD1 b2 ( .I(hi_net), .Z(o2) );
  BUFFD1 b3 ( .I(hi_net), .Z(o3) );

  // Inverter ring: ring_a -> inv1 -> ring_b -> inv2 -> ring_a (cycle).
  INVD1 inv1 ( .I(ring_a), .ZN(ring_b) );
  INVD1 inv2 ( .I(ring_b), .ZN(ring_a) );
  assign ring_out = ring_b;
  assign ring_a = ring_in;

  // Hierarchical submodule for P8: input port sub_in, output port sub_out.
  sub_mod sub_inst ( .si(sub_in), .so(sub_out_net) );
  assign sub_out = sub_out_net;
endmodule

module sub_mod ( input si, output so );
  wire p;
  BUFFD1 sb ( .I(si), .Z(p) );
  assign so = p;
endmodule
