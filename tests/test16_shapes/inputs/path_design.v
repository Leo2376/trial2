// Structural Netlist for Test 5: Path Tracing
// Non-ANSI port style (matches cpu_syn.v golden reference) so the parser
// captures top ports. Cells and pin names match std_cell.lef:
//   BUFFD1   I(in)  Z(out)
//   INVD1    I(in)  ZN(out)
//   OR2D1    A1(in) A2(in) Z(out)
//   AN2D1    A1(in) A2(in) Z(out)

module path_top ( in_a, in_b, out_y );
  input  in_a;
  input  in_b;
  output out_y;

  wire n_and;
  wire n_or;
  wire n_inv;
  wire n_buf;

  AN2D1 g_and ( .A1(in_a), .A2(in_b), .Z(n_and) );
  OR2D1 g_or  ( .A1(in_a), .A2(in_b), .Z(n_or)  );
  INVD1 g_inv ( .I(n_and), .ZN(n_inv) );
  BUFFD1 g_buf ( .I(n_inv), .Z(n_buf) );

  assign out_y = n_buf;

endmodule
