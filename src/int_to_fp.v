// src/int_to_fp.v
// 功能：将64位带符号整数转换为双精度浮点数

`default_nettype none

module int_to_fp (
    input  wire [63:0] int_in,
    output wire [63:0] fp_out
);

    wire sign = int_in[63];
    wire [63:0] abs_val = sign ? -int_in : int_in;

    // --- 处理特殊情况：输入为0 ---
    wire is_zero = (abs_val == 0);

    // --- 常规路径 ---
    // 阶段 1: 规格化 - 找前导零
    wire [6:0] lzc_count;
    lzc_64 lzc( .data_in(abs_val), .count(lzc_count) );

    // 阶段 2: 计算指数和预处理尾数
    wire [11:0] norm_exp;
    wire [63:0] temp_mant;
    
    // 指数 = MSB位置 + Bias = (63 - lzc) + 1023
    assign norm_exp = (63 - lzc_count) + 1023;
    // 左移去掉前导零和MSB的'1'
    assign temp_mant = abs_val << (lzc_count + 1);

    // 阶段 3: 准备舍入
    wire [52:0] mant_for_rounding = {1'b1, temp_mant[63:12]}; // 构造1.M格式
    wire g = temp_mant[11];
    wire r = temp_mant[10];
    wire s = |(temp_mant[9:0]);

    // 阶段 4: 舍入
    wire [52:0] rounded_mant;
    wire        round_carry_out;

    fp_rounder rounder (
        .mant_in(mant_for_rounding),
        .g(g), .r(r), .s(s),
        .mant_out(rounded_mant),
        .carry_out(round_carry_out)
    );
    
    // 阶段 5: 组合最终结果
    wire [10:0] final_exp;
    wire [51:0] final_mant;

    // 检查舍入进位
    assign final_exp = round_carry_out ? (norm_exp + 1) : norm_exp;
    // 如果进位，尾数部分为0 (1.11..1 -> 10.0..0)
    assign final_mant = round_carry_out ? 52'b0 : rounded_mant[51:0];

    // 最终输出选择
    assign fp_out = is_zero ? 64'd0 : {sign, final_exp, final_mant};

endmodule

`default_nettype wire
