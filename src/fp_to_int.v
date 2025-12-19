// src/fp_to_int.v
// 功能：将双精度浮点数转换为64位带符号整数

`default_nettype none

module fp_to_int (
    input  wire [63:0] fp_in,
    output wire [63:0] int_out
);

    // --- 阶段 1: 分解 ---
    wire        sign;
    wire [11:0] exponent; // 带符号指数
    wire [52:0] mantissa;
    wire        is_nan, is_inf, is_zero;

    fp_decomposer decomposer (
        .fp_in(fp_in), .sign(sign), .exponent(exponent), .mantissa(mantissa),
        .is_nan(is_nan), .is_inf(is_inf), .is_zero(is_zero)
    );

    // --- 阶段 2: 计算转换 ---
    reg [63:0] result;
    
    // 这是一个组合逻辑模块
    always @(*) begin
        if (is_nan || is_inf || is_zero || exponent < 0) begin
            // NaN, Inf, Zero, 或绝对值小于1的数都转换为0
            result = 64'd0;
        end else if (exponent >= 63) begin
            // 溢出情况，返回饱和值
            if (sign)
                result = 64'h8000000000000000; // Most negative
            else
                result = 64'h7FFFFFFFFFFFFFFF; // Most positive
        end else begin
            // 常规转换
            // shift_amount = 52 - E
            // magnitude = mantissa >> (52 - E)
            wire [63:0] magnitude;
            wire [5:0] shift_right_amount = 52 - exponent;
            magnitude = {11'b0, mantissa} >> shift_right_amount;

            if (sign)
                result = -magnitude; // 二的补码
            else
                result = magnitude;
        end
    end

    assign int_out = result;

endmodule

`default_nettype wire
