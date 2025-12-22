`default_nettype none

module fp_mul (
    input  wire [63:0] a,
    input  wire [63:0] b,
    output wire [63:0] res
);

    //================================================================
    // 1. 输入分解 (Decomposition)
    //================================================================
    wire sign_a, sign_b;
    wire signed [11:0] exp_a, exp_b; // 真实指数
    wire [52:0] mant_a, mant_b;      // 1.xxxx 或 0.xxxx
    wire is_nan_a, is_inf_a, is_zero_a, is_denorm_a;
    wire is_nan_b, is_inf_b, is_zero_b, is_denorm_b;

    fp_decomposer u_dec_a (
        .fp_in(a),
        .sign(sign_a), .exponent(exp_a), .mantissa(mant_a),
        .is_nan(is_nan_a), .is_inf(is_inf_a), .is_zero(is_zero_a), .is_denormalized(is_denorm_a)
    );

    fp_decomposer u_dec_b (
        .fp_in(b),
        .sign(sign_b), .exponent(exp_b), .mantissa(mant_b),
        .is_nan(is_nan_b), .is_inf(is_inf_b), .is_zero(is_zero_b), .is_denormalized(is_denorm_b)
    );

    //================================================================
    // 2. 核心计算 (Calculation)
    //================================================================
    
    // 2.1 符号位计算
    wire res_sign = sign_a ^ sign_b;

    // 2.2 尾数乘法 (53 bits * 53 bits = 106 bits)
    // 结果格式: Integer bits at [105:104], Fraction at [103:0]
    wire [105:0] product = mant_a * mant_b;

    // 2.3 指数预计算 (真实指数相加)
    // 使用宽一点的位宽以防止加法溢出，后面再检查边界
    wire signed [13:0] exp_sum = exp_a + exp_b;

    // 2.4 规范化与提取舍入位 (Normalization & Extraction)
    // 乘积最高位可能是 1x.xxxx... (需要右移) 或 01.xxxx... (无需移位)
    // 我们假设输入是非零数。如果输入是 Denorm，乘积可能很小，这里简化处理，
    // 主要针对规范化结果，过小的结果在后面会被 Flush-to-Zero。
    
    reg [52:0] mant_for_round;
    reg        guard_bit;
    reg        round_bit;
    reg        sticky_bit;
    reg signed [13:0] exp_norm;

    always @(*) begin
        mant_for_round = 53'b0;
        guard_bit      = 1'b0;
        round_bit      = 1'b0;
        sticky_bit     = 1'b0;
        exp_norm       = exp_sum;
        if (product[105]) begin
            // 情况 1: 结果 >= 2.0 (例如 1.5 * 1.5 = 2.25 -> 10.010...)
            // 动作: 右移 1 位，指数 + 1
            mant_for_round = product[105:53]; // 取高 53 位
            guard_bit      = product[52];
            round_bit      = product[51];
            sticky_bit     = |product[50:0];  // 剩余位做 Sticky
            exp_norm       = exp_sum + 14'sd1;
        end else begin
            // 情况 2: 结果 < 2.0 (例如 1.0 * 1.0 = 1.0 -> 01.00...)
            // 动作: 不需要移位
            mant_for_round = product[104:52]; // 取次高 53 位
            guard_bit      = product[51];
            round_bit      = product[50];
            sticky_bit     = |product[49:0];
            exp_norm       = exp_sum;
        end
    end

    //================================================================
    // 3. 舍入 (Rounding)
    //================================================================
    wire [52:0] mant_rounded;
    wire        round_carry;

    fp_rounder u_rounder (
        .mant_in(mant_for_round),
        .g(guard_bit),
        .r(round_bit),
        .s(sticky_bit),
        .mant_out(mant_rounded),
        .carry_out(round_carry)
    );

    //================================================================
    // 4. 后处理与异常检查 (Post-Processing)
    //================================================================

    // 4.1 处理舍入后的进位
    // 如果舍入导致进位 (例如 1.11...1 -> 10.00...0)，指数需要再次 +1
    wire signed [13:0] exp_final_unbiased = exp_norm + {13'b0, round_carry};

    // 4.2 计算加偏置后的指数 (Biased Exponent, Bias = 1023)
    wire signed [13:0] exp_biased = exp_final_unbiased + 14'sd1023;

    // 4.3 检查上溢 (Overflow) 和下溢 (Underflow)
    // 指数 >= 2047 (0x7FF) 为 Inf/NaN 区域 -> 溢出
    // 指数 <= 0 为 Denorm/Zero 区域 -> 下溢 (本设计简化为 Flush-to-Zero)
    wire is_overflow  = (exp_biased >= 14'sd2047);
    wire is_underflow = (exp_biased <= 14'sd0);

    //================================================================
    // 5. 特殊情况逻辑 (Exception Logic)
    //================================================================
    
    // 判断最终结果是否为 NaN
    // 1. 输入任意一个是 NaN
    // 2. 0 * Inf 或 Inf * 0 (无效运算)
    wire is_nan_res = is_nan_a | is_nan_b | 
                      ((is_zero_a & is_inf_b) | (is_inf_a & is_zero_b));

    // 判断最终结果是否为 Inf
    // 1. 运算结果溢出
    // 2. Inf * 非零有限数
    // 3. (注意：排除掉已判定为 NaN 的情况)
    wire is_inf_res = (is_overflow | is_inf_a | is_inf_b) & ~is_nan_res & ~is_zero_a & ~is_zero_b;

    // 判断最终结果是否为 Zero
    // 1. 运算结果下溢
    // 2. Zero * 有限数
    // 3. (注意：排除掉 NaN)
    wire is_zero_res = (is_underflow | is_zero_a | is_zero_b) & ~is_nan_res & ~is_inf_res;

    //================================================================
    // 6. 结果重组 (Recomposition)
    //================================================================
    
    // 准备传给 recomposer 的字段
    // 指数场：取低 11 位。如果下溢或溢出，由标志位控制，这里的值会被忽略或覆盖
    wire [10:0] final_exp_field = exp_biased[10:0];

    // 尾数场：取舍入后尾数的低 52 位 (去除隐含的 1)
    // 如果 round_carry=1, mant_rounded[52]是0, [51:0]全是0 (正确)
    // 如果 round_carry=0, mant_rounded[52]是1, [51:0]是小数部分 (正确)
    wire [51:0] final_mant_field = mant_rounded[51:0];

    fp_recomposer u_recomp (
        .final_sign(res_sign),
        .final_exponent_field(final_exp_field),
        .final_mantissa_field(final_mant_field),
        
        .is_nan_out(is_nan_res),
        .is_inf_out(is_inf_res),
        .is_zero_out(is_zero_res),
        
        .fp_out(res)
    );

endmodule
`default_nettype wire
