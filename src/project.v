module ram #(parameter F = "program.hex") (
    input wire clk,
    input wire [15:0] addr,
    input wire [39:0] data,
    input wire we,
    output wire [39:0] out
);

    reg [39:0] mem [0:65535];

    initial $readmemh(F, mem); // program.

    always @(posedge clk ) begin
        if (we)
            mem[addr] <= data;
    end

    assign out = mem[addr];

endmodule

module pc(
    input  wire        clk,
    input  wire        rst,
    input  wire        we,     
    input  wire        je,     
    input  wire [15:0] addr,    
    output wire [15:0] out
);
    reg [15:0] count;

    always @(posedge clk) begin
        if (rst)
            count <= 0;
        else if (we) begin
            if (je) count <= addr;
            else    count <= count + 1;
        end
    end

    assign out = count;
endmodule

module alu (
    input wire [7:0] a, // First part of ALU
    input wire [7:0] b, // Second part of ALU
    input wire [7:0] c,
    input wire [3:0] sel, // Selector for operation ( MUX )
    output wire [7:0] out // IPO cycle O for selected operation ( =A <O> B )
);

    /*
    
    ADD - +
    SUB - -
    MUL - *
    DIV - /
    SLA - >>    
    SRA - <<
    FMA - * +
    
    */

    assign out = (sel == 4'b0101) ? (a + b)  :
                 (sel == 4'b0110) ? (a - b)  :
                 (sel == 4'b0111) ? (a * b)  :
                 (sel == 4'b1000) ? (a / b)  :
                 (sel == 4'b1001) ? (a << b) :
                 (sel == 4'b1010) ? (a >> b) : 
                 (sel == 4'b1011) ? (a * b + c) : 8'b0;

endmodule

module register(
    input  wire       clk,
    input  wire       we,
    input  wire [7:0] d,
    output reg  [7:0] q
);
    always @(posedge clk) begin
        if (we)
            q <= d;
    end
endmodule

module core #(parameter F = "program.hex") (
    input wire clk,
    input wire rst,
    input wire [7:0] in_d,
    output wire [55:0] gpio
);

    wire [15:0] pc_out;
    wire [39:0] instr;

    reg [7:0] regs [0:15];
    reg zero;
    
    wire [7:0]  opcode = instr[39:32];
    wire [3:0]  src    = instr[31:28];
    wire [3:0]  dest   = instr[27:24];
    wire [15:0] addr   = instr[23:8];
    wire [7:0]  imm    = instr[7:0];

    wire run  = (opcode != 8'h00);  
    wire jump = (opcode == 8'h03) && (imm == 0 || zero);

    pc counter (
        .clk(clk), .rst(rst), .we(run),
        .je(jump), .addr(addr), .out(pc_out)
    );

    ram #(.F(F)) imem (
        .clk(clk), .addr(pc_out), .data(40'd0), .we(1'b0), .out(instr)
    );

    wire [7:0] alu_out; 
    alu _alu (
        .a(regs[dest]), .b(regs[src]), .c(regs[2]), .sel(opcode[3:0]), .out(alu_out)
    );

    integer i;

    always @(posedge clk ) begin
        if (rst) begin
            zero <= 0;
            for (i = 0; i < 16; i = i + 1) regs[i] <= 8'd0;
        end else begin
            case (opcode)
                8'h01: regs[dest] <= regs[src];            // MOV
                8'h02: regs[dest] <= imm;                  // LEA
                8'h04: zero <= (regs[dest] == regs[src]);  // CMP
                8'h05, 8'h06, 8'h07,
                8'h08, 8'h09, 8'h0A, 8'h0B: regs[dest] <= alu_out; // math
                8'h0C: regs[dest] <= in_d;
                default: ;
            endcase
        end
    end

    // GPIO boxes 9 -> 15 in regs list
    assign gpio = {regs[15], regs[14], regs[13], regs[12],
               regs[11], regs[10], regs[9]};
endmodule


module chip #(
    parameter T1 = "a.hex",
    parameter T2 = "b.hex"
) (
    input  wire         clk,
    input  wire         rst,
    output wire [111:0] gpio
);
    wire [55:0] g0;
    wire [55:0] g1;

    core #(.F(T1)) c0 (.clk(clk), .rst(rst), .in_d(g1[7:0]), .gpio(g0));
    core #(.F(T2)) c1 (.clk(clk), .rst(rst), .in_d(g0[7:0]), .gpio(g1));

    assign gpio = {g1, g0};
endmodule
