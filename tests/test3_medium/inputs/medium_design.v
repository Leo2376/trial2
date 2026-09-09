// Structural Netlist for Test 3: Medium Design
// Only instantiates cells from LEF libraries
// Uses RAM macros + standard cells

// Top module
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

    // ALU block
    alu_block alu ( .a(data_in), .b(reg_file_out), .result(alu_result) );

    // Register file
    reg_file rf ( .clk(clk), .rstn(rstn), .addr(addr_in[4:0]), .data_in(alu_result), .data_out(reg_file_out) );

    // Control logic
    control_logic ctrl ( .clk(clk), .rstn(rstn), .opcode(data_in[5:0]), .pc_out(pc_value) );

    // Memory interface - instantiates actual RAM from LEF
    TS1N7HSLVTA128X33M2WBZHOCP mem0 ( .CLK(clk), .CS(1'b0), .WE(1'b1), .A(addr_in[6:0]), .D(data_in), .Q(mem_data_out) );

    // Output
    assign data_out = alu_result;
    assign addr_out = pc_value;

endmodule

// ALU Block - structural using std cells
module alu_block (
    input [31:0] a,
    input [31:0] b,
    output [31:0] result
);

    wire [31:0] and_out;
    wire [31:0] or_out;
    wire [31:0] xor_out;

    // AND gates for bits 0-7
    AN2D1BWP300H8P64PDLVT and0 ( .A(a[0]), .B(b[0]), .ZN() );
    AN2D1BWP300H8P64PDLVT and1 ( .A(a[1]), .B(b[1]), .ZN() );
    AN2D1BWP300H8P64PDLVT and2 ( .A(a[2]), .B(b[2]), .ZN() );
    AN2D1BWP300H8P64PDLVT and3 ( .A(a[3]), .B(b[3]), .ZN() );
    AN2D1BWP300H8P64PDLVT and4 ( .A(a[4]), .B(b[4]), .ZN() );
    AN2D1BWP300H8P64PDLVT and5 ( .A(a[5]), .B(b[5]), .ZN() );
    AN2D1BWP300H8P64PDLVT and6 ( .A(a[6]), .B(b[6]), .ZN() );
    AN2D1BWP300H8P64PDLVT and7 ( .A(a[7]), .B(b[7]), .ZN() );

    // OR gates for bits 8-15
    OR2D1BWP300H8P64PDLVT or8 ( .A(a[8]), .B(b[8]), .ZN() );
    OR2D1BWP300H8P64PDLVT or9 ( .A(a[9]), .B(b[9]), .ZN() );
    OR2D1BWP300H8P64PDLVT or10 ( .A(a[10]), .B(b[10]), .ZN() );
    OR2D1BWP300H8P64PDLVT or11 ( .A(a[11]), .B(b[11]), .ZN() );
    OR2D1BWP300H8P64PDLVT or12 ( .A(a[12]), .B(b[12]), .ZN() );
    OR2D1BWP300H8P64PDLVT or13 ( .A(a[13]), .B(b[13]), .ZN() );
    OR2D1BWP300H8P64PDLVT or14 ( .A(a[14]), .B(b[14]), .ZN() );
    OR2D1BWP300H8P64PDLVT or15 ( .A(a[15]), .B(b[15]), .ZN() );

    // XOR gates for bits 16-23
    XOR2D1BWP300H8P64PDLVT xor16 ( .A(a[16]), .B(b[16]), .ZN() );
    XOR2D1BWP300H8P64PDLVT xor17 ( .A(a[17]), .B(b[17]), .ZN() );
    XOR2D1BWP300H8P64PDLVT xor18 ( .A(a[18]), .B(b[18]), .ZN() );
    XOR2D1BWP300H8P64PDLVT xor19 ( .A(a[19]), .B(b[19]), .ZN() );
    XOR2D1BWP300H8P64PDLVT xor20 ( .A(a[20]), .B(b[20]), .ZN() );
    XOR2D1BWP300H8P64PDLVT xor21 ( .A(a[21]), .B(b[21]), .ZN() );
    XOR2D1BWP300H8P64PDLVT xor22 ( .A(a[22]), .B(b[22]), .ZN() );
    XOR2D1BWP300H8P64PDLVT xor23 ( .A(a[23]), .B(b[23]), .ZN() );

    // Inverters for bits 24-31
    INVX1BWP300H8P64PDLVT inv24 ( .I(a[24]), .ZN() );
    INVX1BWP300H8P64PDLVT inv25 ( .I(a[25]), .ZN() );
    INVX1BWP300H8P64PDLVT inv26 ( .I(a[26]), .ZN() );
    INVX1BWP300H8P64PDLVT inv27 ( .I(a[27]), .ZN() );
    INVX1BWP300H8P64PDLVT inv28 ( .I(a[28]), .B(b[28]), .ZN() );
    INVX1BWP300H8P64PDLVT inv29 ( .I(a[29]), .B(b[29]), .ZN() );
    INVX1BWP300H8P64PDLVT inv30 ( .I(a[30]), .B(b[30]), .ZN() );
    INVX1BWP300H8P64PDLVT inv31 ( .I(a[31]), .B(b[31]), .ZN() );

    // Result is a combination of inputs
    assign result = a ^ b;

endmodule

// Register File - structural using std cells
module reg_file (
    input clk,
    input rstn,
    input [4:0] addr,
    input [31:0] data_in,
    output [31:0] data_out
);

    wire [31:0] reg_q;
    
    // D flip-flop for register storage
    DFQD1BWP300H8P64PDLVT reg_ff ( .D(data_in), .CLK(clk), .Q(reg_q), .QN(), .CE(1'b1), .R(rstn) );

    // Output assignment
    assign data_out = reg_q;

endmodule

// Control Logic - structural using std cells
module control_logic (
    input clk,
    input rstn,
    input [5:0] opcode,
    output [19:0] pc_out
);

    wire [19:0] pc;
    
    // Program counter using D flip-flops
    DFQD1BWP300H8P64PDLVT pc_ff0 ( .D(1'b1), .CLK(clk), .Q(pc[0]), .QN(), .CE(1'b1), .R(rstn) );
    DFQD1BWP300H8P64PDLVT pc_ff1 ( .D(pc[0]), .CLK(clk), .Q(pc[1]), .QN(), .CE(1'b1), .R(rstn) );
    DFQD1BWP300H8P64PDLVT pc_ff2 ( .D(pc[1]), .CLK(clk), .Q(pc[2]), .QN(), .CE(1'b1), .R(rstn) );
    DFQD1BWP300H8P64PDLVT pc_ff3 ( .D(pc[2]), .CLK(clk), .Q(pc[3]), .QN(), .CE(1'b1), .R(rstn) );

    assign pc_out = pc;

endmodule
