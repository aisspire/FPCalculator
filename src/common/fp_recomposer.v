// src/common/fp_recomposer.v
// 功能：将最终计算好的符号、指数场和尾数场组合为64位双精度浮点数。
// 职责：纯粹的位拼接，所有关于上溢/下溢/规格化的决策都在上游模块完成。

`default_nettype none

module fp_recomposer (
    input  wire        final_sign,          // 最终的符号位
    input  wire [10:0] final_exponent_field, // 最终的11位指数场 (已编码)
    input  wire [51:0] final_mantissa_field, // 最终的52位尾数场
    
    // 特殊值标志，由上游逻辑计算得出
    input  wire        is_nan_out,
    input  wire        is_inf_out,
    input  wire        is_zero_out,
    
    output wire [63:0] fp_out               // 输出的64位浮点数
);

    // 组合逻辑非常直接：
    // 1. 检查是否为 NaN
    // 2. 检查是否为无穷大
    // 3. 检查是否为零 (当符号位为1时，可以正确生成 -0)
    // 4. 如果都不是，则按正常方式组合符号、指数和尾数。
    //    此时，(指数场, 尾数场) 的组合已经可以正确表示规格化数、非规格化数。
    //    例如: (00...0,非零) -> 非规格化数, (非0非FF, 任意) -> 规格化数

    assign fp_out =  (is_nan_out)  ? 64'h7FF8000000000001 :      // 输出一个标准的 Quiet NaN
                     (is_inf_out)  ? {final_sign, 11'h7FF, 52'h0} :
                     (is_zero_out) ? {final_sign, 11'h000, 52'h0} :
                     /* 正常组合 */ {final_sign, final_exponent_field, final_mantissa_field};

endmodule

`default_nettype wire
