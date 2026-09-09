// Structural Netlist for Test 4: Hierarchical Design
// Only instantiates cells from LEF libraries
// Separate hierarchies for RAM macros and standard cells

// Top module
module hierarchical_top (
    input clk,
    input rstn,
    input [31:0] data_in,
    output [31:0] data_out
);

    wire [31:0] ram_data;
    wire [31:0] stdcell_data;

    // RAM Hierarchy
    ram_block ram_hier ( .clk(clk), .addr(data_in[19:0]), .data_in(data_in[31:0]), .data_out(ram_data) );

    // Standard Cell Hierarchy
    stdcell_block std_hier ( .clk(clk), .rstn(rstn), .input(ram_data[31:0]), .output(stdcell_data) );

    // Output
    assign data_out = stdcell_data;

endmodule

// ============================================
// RAM Hierarchy
// ============================================

// RAM Block (hierarchical container)
module ram_block (
    input clk,
    input [19:0] addr,
    input [31:0] data_in,
    output [31:0] data_out
);

    wire [31:0] itag_data;
    wire [31:0] idata_data;

    // Instruction Tag Memory Group
    itag_mem_group itag ( .clk(clk), .addr(addr[19:0]), .data_in(data_in[31:0]), .data_out(itag_data) );

    // Instruction Data Memory Group
    idata_mem_group idata ( .clk(clk), .addr(addr[19:0]), .data_in(data_in[31:0]), .data_out(idata_data) );

    // Combine outputs using std cells
    OR2D1BWP300H8P64PDLVT or_combine0 ( .A(itag_data[0]), .B(idata_data[0]), .ZN() );
    OR2D1BWP300H8P64PDLVT or_combine1 ( .A(itag_data[1]), .B(idata_data[1]), .ZN() );

    // Pass through some bits
    assign data_out[0] = itag_data[0];
    assign data_out[1] = itag_data[1];
    assign data_out[2] = itag_data[2];
    assign data_out[3] = itag_data[3];
    assign data_out[4] = idata_data[4];
    assign data_out[5] = idata_data[5];
    assign data_out[6] = idata_data[6];
    assign data_out[7] = idata_data[7];
    assign data_out[8] = itag_data[8];
    assign data_out[9] = idata_data[9];
    assign data_out[10] = itag_data[10];
    assign data_out[11] = idata_data[11];
    assign data_out[12] = itag_data[12];
    assign data_out[13] = idata_data[13];
    assign data_out[14] = itag_data[14];
    assign data_out[15] = idata_data[15];
    assign data_out[16] = itag_data[16];
    assign data_out[17] = idata_data[17];
    assign data_out[18] = itag_data[18];
    assign data_out[19] = idata_data[19];
    assign data_out[20] = itag_data[20];
    assign data_out[21] = idata_data[21];
    assign data_out[22] = itag_data[22];
    assign data_out[23] = idata_data[23];
    assign data_out[24] = itag_data[24];
    assign data_out[25] = idata_data[25];
    assign data_out[26] = itag_data[26];
    assign data_out[27] = idata_data[27];
    assign data_out[28] = itag_data[28];
    assign data_out[29] = idata_data[29];
    assign data_out[30] = itag_data[30];
    assign data_out[31] = idata_data[31];

endmodule

// Instruction Tag Memory Group
module itag_mem_group (
    input clk,
    input [19:0] addr,
    input [31:0] data_in,
    output [31:0] data_out
);

    wire [31:0] mem0_out;
    wire [31:0] mem1_out;

    // Two RAM instances from LEF
    TS1N7HSLVTA128X33M2WBZHOCP itag_ram_0 ( .CLK(clk), .CS(1'b0), .WE(1'b1), .A(addr[6:0]), .D(data_in), .Q(mem0_out) );
    TS1N7HSLVTA512X40M2WBZHOCP itag_ram_1 ( .CLK(clk), .CS(1'b0), .WE(1'b1), .A(addr[8:0]), .D(data_in), .Q(mem1_out) );

    // Combine outputs
    assign data_out = mem0_out ^ mem1_out;

endmodule

// Instruction Data Memory Group
module idata_mem_group (
    input clk,
    input [19:0] addr,
    input [31:0] data_in,
    output [31:0] data_out
);

    wire [31:0] memh_out;
    wire [31:0] meml_out;

    // RAM instances from LEF
    TS1N7HSLVTA512X40M4WBZHOCP idata_ram_h ( .CLK(clk), .CS(1'b0), .WE(1'b1), .A(addr[8:0]), .D(data_in), .Q(memh_out) );
    TS1N7HSLVTA128X33M4WBZHOCP idata_ram_l ( .CLK(clk), .CS(1'b0), .WE(1'b1), .A(addr[6:0]), .D(data_in), .Q(meml_out) );

    assign data_out = memh_out + meml_out;

endmodule

// ============================================
// Standard Cell Hierarchy
// ============================================

// Standard Cell Block (hierarchical container)
module stdcell_block (
    input clk,
    input rstn,
    input [31:0] input,
    output [31:0] output
);

    wire [31:0] alu_out;
    wire [31:0] logic_out;
    wire [31:0] decode_out;

    // ALU Sub-block
    stdcell_alu alu ( .clk(clk), .input(input[31:0]), .output(alu_out) );

    // Logic Sub-block
    stdcell_logic logic ( .clk(clk), .input(alu_out[31:0]), .output(logic_out) );

    // Decode Sub-block
    stdcell_decode decode ( .clk(clk), .input(logic_out[31:0]), .output(decode_out) );

    assign output = decode_out;

endmodule

// ALU Sub-block (std cells only)
module stdcell_alu (
    input clk,
    input [31:0] input,
    output [31:0] output
);

    wire [31:0] temp;

    // Logic gates
    AN2D1BWP300H8P64PDLVT and_alu0 ( .A(input[0]), .B(input[1]), .ZN() );
    AN2D1BWP300H8P64PDLVT and_alu1 ( .A(input[2]), .B(input[3]), .ZN() );
    OR2D1BWP300H8P64PDLVT or_alu0 ( .A(input[0]), .B(input[1]), .ZN() );
    OR2D1BWP300H8P64PDLVT or_alu1 ( .A(input[2]), .B(input[3]), .ZN() );
    XOR2D1BWP300H8P64PDLVT xor_alu0 ( .A(input[0]), .B(input[1]), .ZN() );
    XOR2D1BWP300H8P64PDLVT xor_alu1 ( .A(input[2]), .B(input[3]), .ZN() );

    // Flip-flops
    DFQD1BWP300H8P64PDLVT ff_alu0 ( .D(input[0]), .CLK(clk), .Q(temp[0]), .QN(), .CE(1'b1), .R(1'b0) );
    DFQD1BWP300H8P64PDLVT ff_alu1 ( .D(input[1]), .CLK(clk), .Q(temp[1]), .QN(), .CE(1'b1), .R(1'b0) );
    DFQD1BWP300H8P64PDLVT ff_alu2 ( .D(input[2]), .CLK(clk), .Q(temp[2]), .QN(), .CE(1'b1), .R(1'b0) );
    DFQD1BWP300H8P64PDLVT ff_alu3 ( .D(input[3]), .CLK(clk), .Q(temp[3]), .QN(), .CE(1'b1), .R(1'b0) );

    // Pass through
    assign output[0] = temp[0];
    assign output[1] = temp[1];
    assign output[2] = temp[2];
    assign output[3] = temp[3];
    assign output[4] = input[4];
    assign output[5] = input[5];
    assign output[6] = input[6];
    assign output[7] = input[7];
    assign output[8] = input[8];
    assign output[9] = input[9];
    assign output[10] = input[10];
    assign output[11] = input[11];
    assign output[12] = input[12];
    assign output[13] = input[13];
    assign output[14] = input[14];
    assign output[15] = input[15];
    assign output[16] = input[16];
    assign output[17] = input[17];
    assign output[18] = input[18];
    assign output[19] = input[19];
    assign output[20] = input[20];
    assign output[21] = input[21];
    assign output[22] = input[22];
    assign output[23] = input[23];
    assign output[24] = input[24];
    assign output[25] = input[25];
    assign output[26] = input[26];
    assign output[27] = input[27];
    assign output[28] = input[28];
    assign output[29] = input[29];
    assign output[30] = input[30];
    assign output[31] = input[31];

endmodule

// Logic Sub-block (std cells only)
module stdcell_logic (
    input clk,
    input [31:0] input,
    output [31:0] output
);

    AN2D1BWP300H8P64PDLVT and_logic0 ( .A(input[0]), .B(input[1]), .ZN() );
    AN2D1BWP300H8P64PDLVT and_logic1 ( .A(input[2]), .B(input[3]), .ZN() );
    OR2D1BWP300H8P64PDLVT or_logic0 ( .A(input[0]), .B(input[1]), .ZN() );
    OR2D1BWP300H8P64PDLVT or_logic1 ( .A(input[2]), .B(input[3]), .ZN() );

    assign output = input;

endmodule

// Decode Sub-block (std cells only)
module stdcell_decode (
    input clk,
    input [31:0] input,
    output [31:0] output
);

    INVX1BWP300H8P64PDLVT inv_dec0 ( .I(input[0]), .ZN() );
    INVX1BWP300H8P64PDLVT inv_dec1 ( .I(input[1]), .ZN() );
    BUFFD1BWP300H8P64PDLVT buf_dec0 ( .I(input[0]), .Z() );
    BUFFD1BWP300H8P64PDLVT buf_dec1 ( .I(input[1]), .Z() );

    assign output = input;

endmodule
