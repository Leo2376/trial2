// Structural Netlist for Test 2: Small Design
// Only instantiates cells from LEF libraries (std_cell.lef + tcbn07_bwph300l8p64pd_baseat_lvt.lef)
// Uses same format as cpu_syn.v (Synopsys DC output)

// Top module - simple counter-like structure
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
    wire net5, net6, net7, net8;
    wire net9, net10, net11, net12;

    // Flip-flop chain using D flip-flops from std cell library
    SDFQD1BWP300H8P64PDLVT ff0 ( .D(enable), .CLK(clk), .Q(net1), .QN(net9), .CE(net5), .R(net6) );
    SDFQD1BWP300H8P64PDLVT ff1 ( .D(net1), .CLK(clk), .Q(net2), .QN(net10), .CE(net5), .R(net6) );
    SDFQD1BWP300H8P64PDLVT ff2 ( .D(net2), .CLK(clk), .Q(net3), .QN(net11), .CE(net5), .R(net6) );
    SDFQD1BWP300H8P64PDLVT ff3 ( .D(net3), .CLK(clk), .Q(net4), .QN(net12), .CE(net5), .R(net6) );

    // Clock enable logic
    INVX1BWP300H8P64PDLVT inv_reset ( .I(reset), .ZN(net5) );

    // Reset logic
    BUFFD1BWP300H8P64PDLVT buf_reset ( .I(reset), .Z(net6) );

    // Output buffers
    BUFFD1BWP300H8P64PDLVT buf0 ( .I(net1), .Z(out0) );
    BUFFD1BWP300H8P64PDLVT buf1 ( .I(net2), .Z(out1) );
    BUFFD1BWP300H8P64PDLVT buf2 ( .I(net3), .Z(out2) );
    BUFFD1BWP300H8P64PDLVT buf3 ( .I(net4), .Z(out3) );

endmodule

// Wrapper module for hierarchy testing
module counter_wrapper (
    input clk,
    input reset,
    input enable,
    output [3:0] count
);

    wire out0, out1, out2, out3;

    simple_counter sc ( .clk(clk), .reset(reset), .enable(enable), .out0(out0), .out1(out1), .out2(out2), .out3(out3) );

endmodule
