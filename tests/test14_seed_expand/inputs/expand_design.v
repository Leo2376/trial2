module top ( clk, rstn, in_a, in_b, out_y );
  input clk, rstn, in_a, in_b;
  output out_y;

  wire n_clk, n_rstn, n_a, n_b;
  wire big_chain, big_out, sub_a_out, sub_b_out;
  wire res_y;

  // Flat top-level leaf cells (live directly in top, no hierarchy):
  // these are legitimate top-residual.
  INVD1 u_top_inv0 ( .I(clk), .ZN(n_clk) );
  INVD1 u_top_inv1 ( .I(rstn), .ZN(n_rstn) );
  INVD1 u_top_inv2 ( .I(in_a), .ZN(n_a) );
  INVD1 u_top_inv3 ( .I(in_b), .ZN(n_b) );

  // One large hierarchical child holding most of the design.
  // It contains BOTH direct-resident leaf cells AND two submodules, so
  // the seed_placement size-driven descent must expand it (>25% of cells),
  // after which its direct-resident cells would leak to top-residual
  // without the expandparent anchor fix.
  big_mod core0 ( .clk(n_clk), .rstn(n_rstn), .a(n_a), .b(n_b), .y(big_out) );

  // A flop at top to act as a sync endpoint.
  DFQD0 u_top_flop ( .CP(n_clk), .D(big_out), .Q(res_y) );

  assign out_y = res_y;
endmodule

module big_mod ( clk, rstn, a, b, y );
  input clk, rstn, a, b;
  output y;

  wire chain [0:31];
  wire sub_a_out, sub_b_out;

  // Direct-resident leaf cells in big_mod: a 32-deep inverter chain.
  // These are the cells that must anchor to big_mod's expanded child
  // (not leak to top-residual) once big_mod is expanded on the frontier.
  INVD1 i0 ( .I(a), .ZN(chain[0]) );
  INVD1 i1 ( .I(chain[0]), .ZN(chain[1]) );
  INVD1 i2 ( .I(chain[1]), .ZN(chain[2]) );
  INVD1 i3 ( .I(chain[2]), .ZN(chain[3]) );
  INVD1 i4 ( .I(chain[3]), .ZN(chain[4]) );
  INVD1 i5 ( .I(chain[4]), .ZN(chain[5]) );
  INVD1 i6 ( .I(chain[5]), .ZN(chain[6]) );
  INVD1 i7 ( .I(chain[6]), .ZN(chain[7]) );
  INVD1 i8 ( .I(chain[7]), .ZN(chain[8]) );
  INVD1 i9 ( .I(chain[8]), .ZN(chain[9]) );
  INVD1 i10 ( .I(chain[9]), .ZN(chain[10]) );
  INVD1 i11 ( .I(chain[10]), .ZN(chain[11]) );
  INVD1 i12 ( .I(chain[11]), .ZN(chain[12]) );
  INVD1 i13 ( .I(chain[12]), .ZN(chain[13]) );
  INVD1 i14 ( .I(chain[13]), .ZN(chain[14]) );
  INVD1 i15 ( .I(chain[14]), .ZN(chain[15]) );
  INVD1 i16 ( .I(chain[15]), .ZN(chain[16]) );
  INVD1 i17 ( .I(chain[16]), .ZN(chain[17]) );
  INVD1 i18 ( .I(chain[17]), .ZN(chain[18]) );
  INVD1 i19 ( .I(chain[18]), .ZN(chain[19]) );
  INVD1 i20 ( .I(chain[19]), .ZN(chain[20]) );
  INVD1 i21 ( .I(chain[20]), .ZN(chain[21]) );
  INVD1 i22 ( .I(chain[21]), .ZN(chain[22]) );
  INVD1 i23 ( .I(chain[22]), .ZN(chain[23]) );
  INVD1 i24 ( .I(chain[23]), .ZN(chain[24]) );
  INVD1 i25 ( .I(chain[24]), .ZN(chain[25]) );
  INVD1 i26 ( .I(chain[25]), .ZN(chain[26]) );
  INVD1 i27 ( .I(chain[26]), .ZN(chain[27]) );
  INVD1 i28 ( .I(chain[27]), .ZN(chain[28]) );
  INVD1 i29 ( .I(chain[28]), .ZN(chain[29]) );
  INVD1 i30 ( .I(chain[29]), .ZN(chain[30]) );
  INVD1 i31 ( .I(chain[30]), .ZN(chain[31]) );

  // Two submodules inside big_mod so the descent has children to expand into.
  sub_a sa0 ( .clk(clk), .x(chain[15]), .y(sub_a_out) );
  sub_b sb0 ( .clk(clk), .x(chain[31]), .y(sub_b_out) );

  // A flop resident directly in big_mod (also a direct-resident cell).
  DFQD0 bf0 ( .CP(clk), .D(sub_a_out), .Q(y) );
endmodule

module sub_a ( clk, x, y );
  input clk, x;
  output y;
  wire c [0:7];
  INVD1 s0 ( .I(x), .ZN(c[0]) );
  INVD1 s1 ( .I(c[0]), .ZN(c[1]) );
  INVD1 s2 ( .I(c[1]), .ZN(c[2]) );
  INVD1 s3 ( .I(c[2]), .ZN(c[3]) );
  INVD1 s4 ( .I(c[3]), .ZN(c[4]) );
  INVD1 s5 ( .I(c[4]), .ZN(c[5]) );
  INVD1 s6 ( .I(c[5]), .ZN(c[6]) );
  INVD1 s7 ( .I(c[6]), .ZN(c[7]) );
  DFQD0 sf ( .CP(clk), .D(c[7]), .Q(y) );
endmodule

module sub_b ( clk, x, y );
  input clk, x;
  output y;
  wire c [0:7];
  INVD1 t0 ( .I(x), .ZN(c[0]) );
  INVD1 t1 ( .I(c[0]), .ZN(c[1]) );
  INVD1 t2 ( .I(c[1]), .ZN(c[2]) );
  INVD1 t3 ( .I(c[2]), .ZN(c[3]) );
  INVD1 t4 ( .I(c[3]), .ZN(c[4]) );
  INVD1 t5 ( .I(c[4]), .ZN(c[5]) );
  INVD1 t6 ( .I(c[5]), .ZN(c[6]) );
  INVD1 t7 ( .I(c[6]), .ZN(c[7]) );
  DFQD0 tf ( .CP(clk), .D(c[7]), .Q(y) );
endmodule
