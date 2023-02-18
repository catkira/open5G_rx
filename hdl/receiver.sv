`timescale 1ns / 1ns

module receiver
(
    output  reg            [23:0]         out
);

reg [32 - 1: 0] regA;

assign out = {{(24 - 32){1'b0}}, regA};

endmodule

