// Structural netlist for Test 10: report_net wire-length estimation.
// Cells/pins match std_cell.lef:
//   AN2D1   A1(in) A2(in) Z(out)
//   INVD1   I(in)  ZN(out)
//   BUFFD1  I(in)  Z(out)
module wlen_top ( in_a, in_b, out_y );
  input  in_a;
  input  in_b;
  output out_y;
  wire n_and;
  wire n_inv;
  wire n_buf;
  AN2D1  g_and ( .A1(in_a), .A2(in_b), .Z(n_and) );
  INVD1  g_inv ( .I(n_and), .ZN(n_inv) );
  BUFFD1 g_buf ( .I(n_inv), .Z(n_buf)  );
  assign out_y = n_buf;
endmodule
