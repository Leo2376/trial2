// Structural Netlist for Test 5: Path Tracing
// Cells and pin names match std_cell.lef (corrected to the cpu_syn.v golden
// reference):
//   BUFFD1BWP300H8P64PDLVT   I(in)  Z(out)
//   INVD1BWP300H8P64PDLVT    I(in)  ZN(out)
//   OR2D1BWP300H8P64PDLVT    A1(in) A2(in) Z(out)
//   AN2D1BWP300H8P64PDLVT    A1(in) A2(in) Z(out)
// All pins use the LEF names, so report_path can trace through cells.

module path_top (
    input  in_a,
    input  in_b,
    output out_y);

    wire n_and;
    wire n_or;
    wire n_inv;
    wire n_buf;

    // Stage 1: two parallel gates fed by the top inputs
    AN2D1BWP300H8P64PDLVT g_and ( .A1(in_a), .A2(in_b), .Z(n_and) );
    OR2D1BWP300H8P64PDLVT g_or  ( .A1(in_a), .A2(in_b), .Z(n_or)  );

    // Stage 2: inverter fed by the AND gate output
    INVD1BWP300H8P64PDLVT g_inv ( .I(n_and), .ZN(n_inv) );

    // Stage 3: buffer fed by the inverter
    BUFFD1BWP300H8P64PDLVT g_buf ( .I(n_inv), .Z(n_buf) );

    // Output
    assign out_y = n_buf;

endmodule
