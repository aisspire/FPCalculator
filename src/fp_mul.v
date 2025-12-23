`default_nettype none

//================================================================
// 模块名称: fp_mul
// 功能描述: 64位双精度浮点数乘法器 (IEEE 754 Double Precision)
// 关键特性:
//   1. 支持非规约数 (Denormalized) 输入的解析 (视具体 decomposer 实现)
//   2. 乘法结果下溢 (Underflow) 目前采用 Flush-to-Zero (归零) 处理
//   3. 支持舍入模式: 向最近偶数舍入 (Round to Nearest, Ties to Even)
//   4. 处理 NaN, Infinity, Zero 等特殊情况
//================================================================

module fp_mul (
    input  wire [63:0] a,   // 被乘数
    input  wire [63:0] b,   // 乘数
    output wire [63:0] res  // 结果
);

    //================================================================
    // 1. 输入分解 (Decomposition)
    //================================================================
    // 将 IEEE 754 格式分解为符号、真实指数(unbiased)、尾数(含隐含1)
    wire sign_a, sign_b;
    wire signed [11:0] exp_a, exp_b; // 真实指数 = 存储指数 - 1023
    wire [52:0] mant_a, mant_b;      // 格式: 1.xxxx 或 0.xxxx (非规约数)
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
    // 2. 核心计算 (Core Calculation)
    //================================================================
    
    // 2.1 符号位计算
    // 乘法符号遵循异或规则: 同号为正，异号为负
    wire res_sign = sign_a ^ sign_b;

    // 2.2 尾数乘法
    // 输入为 53位 (1位整数 + 52位小数)，输出为 106位
    // 结果范围: [1.0, 4.0) (若均为规约数)
    // 格式: Integer bits at [105:104], Fraction at [103:0]
    wire [105:0] product = mant_a * mant_b;

    // 2.3 指数预计算
    // 直接相加真实指数。使用 14位宽防止加法过程中溢出
    wire signed [13:0] exp_sum = exp_a + exp_b;

    // 2.4 规范化与提取舍入位 (Normalization & Extraction)
    // 乘积结果必然在 [1.0, 4.0) 区间内 (假设非零且忽略非规约数输入极其微小的情况)
    // 需要根据结果大小选择截取位置，并准备 Guard(G), Round(R), Sticky(S) 位
    
    reg [52:0] mant_for_round;  // 待舍入的尾数 (包含隐含的1)
    reg        guard_bit;       // 保护位 (LSB后一位)
    reg        round_bit;       // 舍入位 (G后一位)
    reg        sticky_bit;      // 粘滞位 (R后所有位的逻辑或，表示是否精确)
    reg signed [13:0] exp_norm; // 规范化后的真实指数

    always @(*) begin
        // 初始化
        mant_for_round = 53'b0;
        guard_bit      = 1'b0;
        round_bit      = 1'b0;
        sticky_bit     = 1'b0;
        exp_norm       = exp_sum;

        // 检查乘积最高位 (bit 105)
        if (product[105]) begin
            //------------------------------------------------------
            // 情况 1: 结果 >= 2.0 (例如 1.5 * 1.5 = 2.25 -> 10.01...)
            // 动作: 结果需要右移 1 位以恢复 1.xxxx 格式，同时指数 + 1
            //------------------------------------------------------
            mant_for_round = product[105:53]; // 取 [105] 为整数位
            guard_bit      = product[52];
            round_bit      = product[51];
            sticky_bit     = |product[50:0];  // 剩余低位 OR 运算
            exp_norm       = exp_sum + 14'sd1;
        end else begin
            //------------------------------------------------------
            // 情况 2: 结果 < 2.0 (例如 1.0 * 1.0 = 1.0 -> 01.00...)
            // 动作: 不需要移位，直接截取
            //------------------------------------------------------
            mant_for_round = product[104:52]; // 取 [104] 为整数位
            guard_bit      = product[51];
            round_bit      = product[50];
            sticky_bit     = |product[49:0];
            exp_norm       = exp_sum;
        end
    end

    //================================================================
    // 3. 舍入处理 (Rounding)
    //================================================================
    // 执行 "Round to Nearest, Ties to Even"
    wire [52:0] mant_rounded;
    wire        round_carry;      // 舍入是否导致最高位进位

    fp_rounder u_rounder (
        .mant_in(mant_for_round),
        .g(guard_bit),
        .r(round_bit),
        .s(sticky_bit),
        .mant_out(mant_rounded),
        .carry_out(round_carry)
    );

    //================================================================
    // 4. 后处理与指数偏置 (Post-Processing)
    //================================================================

    // 4.1 处理舍入进位
    // 如果尾数全1 (1.11...1) 且进位 -> 变成 10.00...0，需再次右移并指数+1
    // 这里的 round_carry 通常意味着 mantissa 需要右移，等效于指数加1
    wire signed [13:0] exp_final_unbiased = exp_norm + {13'b0, round_carry};

    // 4.2 计算加偏置后的指数 (Biased Exponent)
    // IEEE 754 双精度 Bias = 1023
    wire signed [13:0] exp_biased = exp_final_unbiased + 14'sd1023;

    // 4.3 边界检查
    // 上溢: 指数 >= 2047 (全1为Inf/NaN)
    // 下溢: 指数 <= 0 (非规约数或零) -> 本设计简化为下溢归零
    wire is_overflow  = (exp_biased >= 14'sd2047);
    wire is_underflow = (exp_biased <= 14'sd0);

    //================================================================
    // 5. 特殊情况与异常逻辑 (Exception Logic)
    //================================================================
    
    // 判定 NaN (Not a Number)
    // 1. 输入本身是 NaN
    // 2. 无效运算: 0 * Inf 或 Inf * 0
    wire is_nan_res = is_nan_a | is_nan_b | 
                      ((is_zero_a & is_inf_b) | (is_inf_a & is_zero_b));

    // 判定 Infinity
    // 1. 运算结果上溢
    // 2. 输入包含 Inf (且非无效运算)
    // 3. 必须排除结果为 NaN 的情况
    wire is_inf_res = (is_overflow | is_inf_a | is_inf_b) & ~is_nan_res & ~is_zero_a & ~is_zero_b;

    // 判定 Zero
    // 1. 运算结果下溢 (Flush-to-Zero)
    // 2. 输入包含 Zero (且非 NaN, 非 Inf)
    wire is_zero_res = (is_underflow | is_zero_a | is_zero_b) & ~is_nan_res & ~is_inf_res;

    //================================================================
    // 6. 结果重组 (Recomposition)
    //================================================================
    
    // 准备指数场: 
    // 若发生 Over/Underflow，fp_recomposer 会根据标志位覆盖此值，
    // 这里只需截取低11位即可。
    wire [10:0] final_exp_field = exp_biased[10:0];

    // 准备尾数场:
    // 取舍入后尾数的低 52 位 (去除隐含的 1)。
    // round_carry 的影响已在指数调整中处理，尾数位直接截取即可。
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
