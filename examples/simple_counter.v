// Simple 4-bit counter
// Uses cells from tcbn07_bwph300l8p64pd_baseat_lvt.lef

module simple_counter (
    input clk,
    input reset_n,
    input enable,
    output [3:0] count
);

    // D flip-flops with enable
    CKLNQD1BWP300H8P64PDLVT ff0 (.CP(clk), .E(enable), .TE(reset_n), .Q(count[0]));
    
    AN2D1BWP300H8P64PDLVT and0 (.A(enable), .B(count[0]), .Y(enable0));
    CKLNQD1BWP300H8P64PDLVT ff1 (.CP(clk), .E(enable0), .TE(reset_n), .Q(count[1]));
    
    AN2D1BWP300H8P64PDLVT and1 (.A(count[0]), .B(count[1]), .Y(temp1));
    AN2D1BWP300H8P64PDLVT and2 (.A(temp1), .B(enable), .Y(enable1));
    CKLNQD1BWP300H8P64PDLVT ff2 (.CP(clk), .E(enable1), .TE(reset_n), .Q(count[2]));
    
    AN2D1BWP300H8P64PDLVT and3 (.A(count[1]), .B(count[2]), .Y(temp2));
    AN2D1BWP300H8P64PDLVT and4 (.A(temp2), .B(count[0]), .Y(temp3));
    AN2D1BWP300H8P64PDLVT and5 (.A(temp3), .B(enable), .Y(enable2));
    CKLNQD1BWP300H8P64PDLVT ff3 (.CP(clk), .E(enable2), .TE(reset_n), .Q(count[3]));

endmodule
