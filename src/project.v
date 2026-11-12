`default_nettype none

module ram (
    input  wire        clk,
    input  wire [3:0]  addr,
    input  wire [39:0] data,
    input  wire        we,
    output wire [39:0] out
);
    reg [39:0] mem [0:15];

    always @(posedge clk) begin
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
            count <= 16'd0;
        else if (we) begin
            if (je) count <= addr;
            else    count <= count + 16'd1;
        end
    end

    assign out = count;
endmodule

module alu (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [7:0] c,
    input  wire [3:0] sel,
    output wire [7:0] out
);
    assign out = (sel == 4'b0101) ? (a + b)  :
                 (sel == 4'b0110) ? (a - b)  :
                 (sel == 4'b0111) ? (a * b)  :
                 (sel == 4'b1001) ? (a << b[2:0]) :
                 (sel == 4'b1010) ? (a >> b[2:0]) : 
                 (sel == 4'b1011) ? (a * b + c) : 8'b0;
endmodule

module core (
    input  wire        clk,
    input  wire        rst,
    input  wire        prog_we,
    input  wire [3:0]  prog_addr,
    input  wire [39:0] prog_data,
    input  wire [7:0]  in_d,
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
    wire jump = (opcode == 8'h03) && (imm == 8'd0 || zero);

    pc counter (
        .clk(clk), .rst(rst), .we(run),
        .je(jump), .addr(addr), .out(pc_out)
    );

    wire [3:0] mem_addr = prog_we ? prog_addr : pc_out[3:0];

    ram imem (
        .clk(clk), .addr(mem_addr), .data(prog_data), .we(prog_we), .out(instr)
    );

    wire [7:0] alu_out; 
    alu _alu (
        .a(regs[dest]), .b(regs[src]), .c(regs[2]), .sel(opcode[3:0]), .out(alu_out)
    );

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            zero <= 1'b0;
            for (i = 0; i < 16; i = i + 1) regs[i] <= 8'd0;
        end else begin
            case (opcode)
                8'h01: regs[dest] <= regs[src];
                8'h02: regs[dest] <= imm;
                8'h04: zero <= (regs[dest] == regs[src]);
                8'h05, 8'h06, 8'h07,
                8'h09, 8'h0A, 8'h0B: regs[dest] <= alu_out;
                8'h0C: regs[dest] <= in_d;
                default: ;
            endcase
        end
    end

    assign gpio = {regs[15], regs[14], regs[13], regs[12],
                   regs[11], regs[10], regs[9]};
endmodule

module chip (
    input  wire         clk,
    input  wire         rst,
    input  wire         prog_we,
    input  wire [3:0]   prog_addr,
    input  wire [39:0]  prog_data,
    output wire [111:0] gpio
);
    wire [55:0] g0;
    wire [55:0] g1;

    core c0 (
        .clk(clk), .rst(rst),
        .prog_we(prog_we), .prog_addr(prog_addr), .prog_data(prog_data),
        .in_d(g1[7:0]), .gpio(g0)
    );
    
    core c1 (
        .clk(clk), .rst(rst),
        .prog_we(prog_we), .prog_addr(prog_addr), .prog_data(prog_data),
        .in_d(g0[7:0]), .gpio(g1)
    );

    assign gpio = {g1, g0};
endmodule

module tt_um_fruzinofruzino_zeron_cpu (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire rst = !rst_n;
    wire [111:0] gpio;

    wire [39:0] prog_data = {ui_in, uio_in, ui_in, uio_in, ui_in};

    chip zeron_dual_core (
        .clk(clk),
        .rst(rst),
        .prog_we(ui_in[7]),
        .prog_addr(ui_in[3:0]),
        .prog_data(prog_data),
        .gpio(gpio)
    );

    assign uo_out  = gpio[7:0];
    assign uio_out = gpio[15:8];
    assign uio_oe  = 8'hFF;

    wire _unused = &{ena, ui_in[6:4], gpio[111:16], 1'b0};
endmodule
