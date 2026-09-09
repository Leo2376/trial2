// Structural Netlist for Test 2: Small Design
// Cells and pin names match std_cell.lef (corrected to the cpu_syn.v golden
// reference):
//   SDFQD1BWP300H8P64PDLVT  D(in) CP(in) SE(in) SI(in) Q(out)
//   INVD1BWP300H8P64PDLVT   I(in) ZN(out)
//   BUFFD1BWP300H8P64PDLVT  I(in) Z(out)

module simple_counter (
    input clk,
    input reset,
    input enable,
    output out0,
    output out1,
    output out2,
    output out3
);

    wire net1, net2, net3, net4;
    wire n_resetb;
    wire n_reset;

    // Flip-flop chain (D flip-flops). SE tied to the reset-bar enable so the
    // scan-enable is held; SI held to reset.
    SDFQD1BWP300H8P64PDLVT ff0 ( .D(enable), .CP(clk), .Q(net1), .SE(n_resetb), .SI(n_reset) );
    SDFQD1BWP300H8P64PDLVT ff1 ( .D(net1), .CP(clk), .Q(net2), .SE(n_resetb), .SI(n_reset) );
    SDFQD1BWP300H8P64PDLVT ff2 ( .D(net2), .CP(clk), .Q(net3), .SE(n_resetb), .SI(n_reset) );
    SDFQD1BWP300H8P64PDLVT ff3 ( .D(net3), .CP(clk), .Q(net4), .SE(n_resetb), .SI(n_reset) );

    // Reset-bar and reset buffer
    INVD1BWP300H8P64PDLVT  inv_reset ( .I(reset), .ZN(n_resetb) );
    BUFFD1BWP300H8P64PDLVT buf_reset ( .I(reset), .Z(n_reset) );

    // Output buffers
    BUFFD1BWP300H8P64PDLVT buf0 ( .I(net1), .Z(out0) );
    BUFFD1BWP300H8P64PDLVT buf1 ( .I(net2), .Z(out1) );
    BUFFD1BWP300H8P64PDLVT buf2 ( .I(net3), .Z(out2) );
    BUFFD1BWP300H8P64PDLVT buf3 ( .I(net4), .Z(out3) );

endmodule

module counter_wrapper (
    input clk,
    input reset,
    input enable,
    output [3:0] count
);

    wire out0, out1, out2, out3;

    simple_counter sc ( .clk(clk), .reset(reset), .enable(enable), .out0(out0), .out1(out1), .out2(out2), .out3(out3) );

endmodule
