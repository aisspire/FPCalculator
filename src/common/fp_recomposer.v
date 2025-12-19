// src/common/fp_recomposer.v
// 功能：将符号、指数、尾数组合为64位双精度浮点数 (简化版，未含舍入)

`default_nettype none

module fp_recomposer (
    input  wire        final_sign,      // 最终的符号位
    input  wire [11:0] final_exponent,  // 最终的指数 (有符号)
    input  wire [52:0] final_mantissa,  // 最终的53位尾数 (含隐藏位)
    
    // 特殊值输入，通常由运算逻辑直接产生
    input  wire        is_nan_out,
    input  wire        is_inf_out,
    input  wire        is_zero_out,
    input  wire        is_denormal_out, // 结果是非规格化数
    output wire [63:0] fp_out           // 输出的64位浮点数
);

    localparam EXP_BIAS      = 1023;
    localparam MAX_EXP       = 1023;
    localparam MIN_EXP       = -1022;

    wire [10:0] biased_exponent;
    wire [51:0] output_mantissa;
    wire        is_overflow;
    wire        is_underflow;

    // 指数溢出检测
    // 上溢: 指数大于规格化数的最大指数
    assign is_overflow = (final_exponent > MAX_EXP);
    // 下溢: 指数小于等于非规格化数的指数 (1-1023)
    assign is_underflow = (final_exponent < MIN_EXP); // 简化判断，精确处理需要考虑舍入

    // 添加偏移量，转为11位无符号指数(这里需要处理负指数的情况)
    assign biased_exponent = final_exponent + EXP_BIAS;

    // 截取尾数（这里是简化的，没有舍入）
    // 真实的实现需要根据 guard, round, sticky 位进行舍入
    assign output_mantissa = final_mantissa[51:0];

    // 组合最终输出
    assign fp_out =  (is_nan_out)                             ? 64'h7FF8000000000001 : // Canonical Quiet NaN
                     (is_inf_out || is_overflow)              ? {final_sign, 11'h7FF, 52'h0} :
                     (is_zero_out || is_underflow)            ? {final_sign, 11'h000, 52'h0} : // 简化处理，下溢直接置零
                     /* 正常情况 */                           {final_sign, biased_exponent, output_mantissa};

endmodule

`default_nettype wire
