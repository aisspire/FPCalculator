// src/common/fp_rounder.v
// 功能：根据G, R, S位实现平衡型舍入(Round to Nearest, Ties to Even)

`default_nettype none

module fp_rounder (
    input  wire [52:0] mant_in,      // 输入的53位尾数 (规格化后的)
    input  wire        g,            // Guard bit
    input  wire        r,            // Round bit
    input  wire        s,            // Sticky bit

    output wire [52:0] mant_out,     // 舍入后的53位尾数
    output wire        carry_out     // 舍入后产生的进位 (例如 1.11...1 + 1 -> 10.00...0)
);

    wire round_decision;
    wire lsb = mant_in[0]; // 待舍入的尾数的最低位

    // 平衡型舍入决策逻辑
    // 当丢弃部分 > 0.5 LSB 时，或
    // 当丢弃部分 = 0.5 LSB 且尾数最低位为1时，向上舍入
    assign round_decision = g & (r | s | lsb);

    // 执行舍入操作：将决策位加到尾数上
    // 使用54位加法器以捕获可能的进位
    wire [53:0] rounded_result;
    assign rounded_result = {1'b0, mant_in} + round_decision;

    // 输出结果
    assign mant_out = rounded_result[52:0];
    assign carry_out = rounded_result[53];

endmodule

`default_nettype wire
