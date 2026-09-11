// Structural Netlist for Test 6: Liberty sync-pin import
// Non-ANSI port style (matches cpu_syn.v golden reference). Uses one flop
// (DFQD0, sync pin CP) and one SRAM
// (SP128X33M2, sync pin CLK) so add_lib sync-pin recovery can
// be validated against a built design.
module sync_top ( clk, data_in, addr, data_out );
  input  clk;
  input  data_in;
  input  addr;
  output data_out;
  wire   q_net;
  wire   qout_net;

  DFQD0 sync_ff ( .D(data_in), .CP(clk), .Q(q_net) );
  SP128X33M2 sync_ram ( .CLK(clk), .A(addr), .D(data_in), .Q(qout_net) );

  assign data_out = q_net & qout_net;
endmodule
