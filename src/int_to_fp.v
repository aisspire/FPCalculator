`default_nettype none

module int_to_fp (
    input  wire [63:0] int_in,
    output wire [63:0] fp_out
);

    // ========================================================================
    // 1. 符号与绝对值处理 (Sign & Magnitude)
    // ========================================================================
    wire sign = int_in[63];
    
    // 如果是负数，取补码获得绝对值；如果是正数，直接使用
    wire [63:0] abs_in = sign ? (~int_in + 1'b1) : int_in;
    
    // 零检测
    wire is_input_zero = (int_in == 64'd0);

    // ========================================================================
    // 2. 规格化 (Normalization) - 寻找最高有效位
    // ========================================================================
    wire [6:0] lzc_count;
    
    // 实例化前导零计数器
    lzc_64 u_lzc (
        .data_in (abs_in),
        .count   (lzc_count)
    );

    // 规格化移位：将有效数据左移，使得最高位 '1' 位于 bit 63
    // 这样方便后续截取 53 位尾数和 G/R/S 位
    wire [63:0] aligned_data = abs_in << lzc_count;

    // ========================================================================
    // 3. 准备舍入逻辑 (Prepare Rounding)
    // ========================================================================
    // 双精度尾数结构：1.F (1位隐含 + 52位显式) = 53位精度
    // aligned_data[63] 对应隐含的 '1'
    // aligned_data[62:11] 对应显式的 52 位小数
    // aligned_data[10] 是 Guard bit
    // aligned_data[9]  是 Round bit
    // aligned_data[8:0] 是 Sticky bits (只要有任意为1，S即为1)

    wire [52:0] mant_pre_round = aligned_data[63:11];
    wire        guard_bit      = aligned_data[10];
    wire        round_bit      = aligned_data[9];
    wire        sticky_bit     = |aligned_data[8:0];

    // ========================================================================
    // 4. 执行舍入 (Rounding)
    // ========================================================================
    wire [52:0] mant_rounded;
    wire        round_carry;

    fp_rounder u_rounder (
        .mant_in   (mant_pre_round),
        .g         (guard_bit),
        .r         (round_bit),
        .s         (sticky_bit),
        .mant_out  (mant_rounded),
        .carry_out (round_carry)
    );

    // ========================================================================
    // 5. 指数计算与调整 (Exponent Calculation)
    // ========================================================================
    // 原始指数计算：
    // 整数的MSB位置在 (63 - lzc_count)。例如值为1时，lzc=63，MSB pos=0，指数应为0。
    // IEEE 754 双精度 Bias 为 1023。
    // 基础指数 = (63 - lzc_count) + 1023 = 1086 - lzc_count
    
    wire [11:0] exp_base = 12'd1086 - {5'b0, lzc_count};
    
    // 如果舍入导致进位 (例如 1.11...1 -> 10.00...0)，指数需要+1
    // 注意：int转double永远不会产生Inf (最大int < 最大double)，也永远不会产生NaN
    wire [10:0] final_exp = exp_base[10:0] + {10'b0, round_carry};

    // 如果舍入进位了，尾数实际上变成了 10.000...，我们需要右移一位归一化
    // 这意味着最终的显式尾数全为0 (因为最高位1变成了隐含位)
    // fp_rounder 的输出如果是进位，mant_rounded 通常是全0，或者是溢出的低位。
    // 简单处理：如果进位，显式尾数直接置0；否则取舍入后结果的低52位。
    wire [51:0] final_mant = round_carry ? 52'd0 : mant_rounded[51:0];

    // ========================================================================
    // 6. 结果重组 (Recomposition)
    // ========================================================================
    
    fp_recomposer u_recomposer (
        .final_sign           (sign),
        .final_exponent_field (final_exp),
        .final_mantissa_field (final_mant),
        
        .is_nan_out           (1'b0),          // Int -> FP 不会产生 NaN
        .is_inf_out           (1'b0),          // Int -> FP 不会溢出到 Inf
        .is_zero_out          (is_input_zero), // 只有输入为0时输出0
        
        .fp_out               (fp_out)
    );

endmodule
`default_nettype wire
