`default_nettype none

// ============================================================================
// Module: int_to_fp
// Description: 将有符号64位整数转换为IEEE 754双精度浮点数
// Pipeline: 无 (组合逻辑)
// ============================================================================
module int_to_fp (
    input  wire [63:0] int_in,
    output wire [63:0] fp_out
);

    // ========================================================================
    // 1. 符号提取与绝对值计算 (Sign & Magnitude)
    // ========================================================================
    wire sign = int_in[63];
    
    // 负数转补码取绝对值，正数保持不变
    wire [63:0] abs_in = sign ? (~int_in + 1'b1) : int_in;
    
    // 特殊情况：输入全0检测
    wire is_input_zero = (int_in == 64'd0);

    // ========================================================================
    // 2. 规格化 (Normalization)
    // ========================================================================
    wire [6:0] lzc_count;
    
    // 前导零计数：确定最高有效位(MSB)的位置
    lzc_64 u_lzc (
        .data_in (abs_in),
        .count   (lzc_count)
    );

    // 左移对齐：将有效数据的MSB移至bit [63]
    // 目的：构造 1.F 格式，便于截取尾数
    wire [63:0] aligned_data = abs_in << lzc_count;

    // ========================================================================
    // 3. 尾数提取与舍入位准备 (Mantissa & G/R/S)
    // ========================================================================
    // 逻辑说明：
    // IEEE双精度需 53位尾数 (1位隐含 + 52位显式)。
    // aligned_data[63]    : 隐含位 (Hidden bit, always 1)
    // aligned_data[62:11] : 显式尾数 (Fraction, 52 bits)
    // aligned_data[10]    : 保护位 (Guard)
    // aligned_data[9]     : 舍入位 (Round)
    // aligned_data[8:0]   : 粘贴位 (Sticky, 任意位为1则置1)

    wire [52:0] mant_pre_round = aligned_data[63:11]; // {1'b1, fraction[51:0]}
    wire        guard_bit      = aligned_data[10];
    wire        round_bit      = aligned_data[9];
    wire        sticky_bit     = |aligned_data[8:0];

    // ========================================================================
    // 4. 执行舍入 (Rounding)
    // ========================================================================
    wire [52:0] mant_rounded;
    wire        round_carry;

    // 根据 G/R/S 位执行就近舍入 (Round to Nearest Even)
    fp_rounder u_rounder (
        .mant_in   (mant_pre_round),
        .g         (guard_bit),
        .r         (round_bit),
        .s         (sticky_bit),
        .mant_out  (mant_rounded),
        .carry_out (round_carry)
    );

    // ========================================================================
    // 5. 指数计算 (Exponent Calculation)
    // ========================================================================
    // 计算公式：
    // 1. 实际指数 Real_Exp = 63 - lzc_count (因为整数小数点在bit 0右侧)
    // 2. 偏移指数 Biased_Exp = Real_Exp + Bias(1023)
    // 3. 简化公式：(63 - lzc) + 1023 = 1086 - lzc
    wire [11:0] exp_base = 12'd1086 - {5'b0, lzc_count};
    
    // 修正进位：若舍入导致尾数溢出 (如 1.11... -> 10.00...)，指数+1
    // 注：Int64最大值未超过Double范围，故无需处理Inf
    wire [10:0] final_exp = exp_base[10:0] + {10'b0, round_carry};

    // 尾数修正：若进位，尾数归一化后显式部分全为0；否则取舍入结果低52位
    wire [51:0] final_mant = round_carry ? 52'd0 : mant_rounded[51:0];

    // ========================================================================
    // 6. 结果重组 (Recomposition)
    // ========================================================================
    fp_recomposer u_recomposer (
        .final_sign           (sign),
        .final_exponent_field (final_exp),
        .final_mantissa_field (final_mant),
        
        // Int -> FP 不会产生 NaN 或 Inf
        .is_nan_out           (1'b0),          
        .is_inf_out           (1'b0),          
        .is_zero_out          (is_input_zero), // 输入为0则强制输出全0
        
        .fp_out               (fp_out)
    );

endmodule
`default_nettype wire
