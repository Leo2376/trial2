// Structural Netlist for Test 3: Medium Design
// Cells and pin names match std_cell.lef (corrected to the cpu_syn.v golden
// reference):
//   AN2D1BWP300H8P64PDLVT   A1(in) A2(in) Z(out)
//   OR2D1BWP300H8P64PDLVT   A1(in) A2(in) Z(out)
//   XOR2D0BWP300H8P64PDLVT   A1(in) A2(in) Z(out)
//   INVD1BWP300H8P64PDLVT    I(in)  ZN(out)
//   DFQD0BWP300H8P64PDLVT    D(in)  CP(in) Q(out)

module medium_cpu (
    input clk,
    input rstn,
    input [31:0] data_in,
    input [19:0] addr_in,
    output [31:0] data_out,
    output [19:0] addr_out
);

    wire [31:0] alu_result;
    wire [31:0] reg_file_out;
    wire [19:0] pc_value;
    wire [31:0] mem_data_out;

    alu_block alu ( .a(data_in), .b(reg_file_out), .result(alu_result) );
    reg_file rf ( .clk(clk), .rstn(rstn), .addr(addr_in[4:0]), .data_in(alu_result), .data_out(reg_file_out) );
    control_logic ctrl ( .clk(clk), .rstn(rstn), .opcode(data_in[5:0]), .pc_out(pc_value) );

    assign data_out = alu_result;
    assign addr_out = pc_value;

endmodule

// ALU Block - structural using std cells (AND/OR/XOR/INV)
module alu_block (
    input [31:0] a,
    input [31:0] b,
    output [31:0] result
);

    // AND gates for bits 0-3
    AN2D1BWP300H8P64PDLVT and0 ( .A1(a[0]), .A2(b[0]), .Z(result[0]) );
    AN2D1BWP300H8P64PDLVT and1 ( .A1(a[1]), .A2(b[1]), .Z(result[1]) );
    AN2D1BWP300H8P64PDLVT and2 ( .A1(a[2]), .A2(b[2]), .Z(result[2]) );
    AN2D1BWP300H8P64PDLVT and3 ( .A1(a[3]), .A2(b[3]), .Z(result[3]) );

    // OR gates for bits 4-7
    OR2D1BWP300H8P64PDLVT or4 ( .A1(a[4]), .A2(b[4]), .Z(result[4]) );
    OR2D1BWP300H8P64PDLVT or5 ( .A1(a[5]), .A2(b[5]), .Z(result[5]) );
    OR2D1BWP300H8P64PDLVT or6 ( .A1(a[6]), .A2(b[6]), .Z(result[6]) );
    OR2D1BWP300H8P64PDLVT or7 ( .A1(a[7]), .A2(b[7]), .Z(result[7]) );

    // XOR gates for bits 8-11
    XOR2D0BWP300H8P64PDLVT xor8  ( .A1(a[8]),  .A2(b[8]),  .Z(result[8])  );
    XOR2D0BWP300H8P64PDLVT xor9  ( .A1(a[9]),  .A2(b[9]),  .Z(result[9])  );
    XOR2D0BWP300H8P64PDLVT xor10 ( .A1(a[10]), .A2(b[10]), .Z(result[10]) );
    XOR2D0BWP300H8P64PDLVT xor11 ( .A1(a[11]), .A2(b[11]), .Z(result[11]) );

    // Inverters for bits 12-15
    INVD1BWP300H8P64PDLVT inv12 ( .I(a[12]), .ZN(result[12]) );
    INVD1BWP300H8P64PDLVT inv13 ( .I(a[13]), .ZN(result[13]) );
    INVD1BWP300H8P64PDLVT inv14 ( .I(a[14]), .ZN(result[14]) );
    INVD1BWP300H8P64PDLVT inv15 ( .I(a[15]), .ZN(result[15]) );

    assign result[31:16] = 16'b0;

endmodule

// Register File - D flip-flop storage
module reg_file (
    input clk,
    input rstn,
    input [4:0] addr,
    input [31:0] data_in,
    output [31:0] data_out
);

    wire [31:0] reg_q;

    DFQD0BWP300H8P64PDLVT reg_ff ( .D(data_in[0]), .CP(clk), .Q(reg_q[0]) );

    assign data_out = reg_q;

endmodule

// Control Logic - program counter D flip-flop chain
module control_logic (
    input clk,
    input rstn,
    input [5:0] opcode,
    output [19:0] pc_out
);

    wire [19:0] pc;

    DFQD0BWP300H8P64PDLVT pc_ff0 ( .D(pc[0]), .CP(clk), .Q(pc[1]) );
    DFQD0BWP300H8P64PDLVT pc_ff1 ( .D(pc[1]), .CP(clk), .Q(pc[2]) );
    DFQD0BWP300H8P64PDLVT pc_ff2 ( .D(pc[2]), .CP(clk), .Q(pc[3]) );

    assign pc[0] = 1'b0;
    assign pc_out = pc;

endmodule
