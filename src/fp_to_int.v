`default_nettype none

module fp_to_int (
    input  wire [63:0] fp_in,
    output reg  [63:0] int_out
);

    // =========================================================================
    // 1. 浮点数分解
    // =========================================================================
    wire        sign;
    wire signed [11:0] exponent;
    wire [52:0] mantissa;
    wire        is_nan;
    wire        is_inf;
    // is_zero, is_denormalized 此处不直接使用，逻辑中已覆盖

    fp_decomposer u_decomposer (
        .fp_in           (fp_in),
        .sign            (sign),
        .exponent        (exponent),
        .mantissa        (mantissa),
        .is_nan          (is_nan),
        .is_inf          (is_inf),
        .is_zero         (), 
        .is_denormalized () 
    );

    // =========================================================================
    // 2. 预处理：准备舍入所需的 G, R, S 位
    // =========================================================================
    
    // 只有当 exponent <= 52 时，才涉及到小数部分的舍入。
    // 如果 exponent > 52，尾数完全位于整数部分，无小数，G=R=S=0。
    
    // 我们构建一个宽的移位寄存器来提取整数部分和小数位。
    // 构造 {mantissa, 64'b0} (共117位)，相当于左对齐。
    // 右移量 = 52 - exponent。
    // 例如：exp=52 -> shift=0,  mantissa全为整数。
    //       exp=0  -> shift=52, mantissa[52]为整数LSB, 其余为小数。
    
    reg [6:0]   r_shift_amt;
    reg [116:0] shifted_mant;
    
    always @(*) begin
        if (exponent <= 52 && exponent >= -60) begin 
            // 正常的转换范围，或者非常小的数（全小数）
            // 注意：exponent 是有符号的，需要处理负数情况
            r_shift_amt = 7'd52 - exponent[6:0]; 
        end else if (exponent < -60) begin
            // 极小的数，完全移出，全为 Sticky
            r_shift_amt = 7'd116; 
        end else begin
            // Exponent > 52，此路径不使用移位逻辑生成小数
            r_shift_amt = 7'd0;
        end
        
        shifted_mant = {mantissa, 64'b0} >> r_shift_amt;
    end

    // 提取送入 Rounder 的信号
    // 整数部分 (送入 mant_in): 位于 shifted_mant 的高 53 位 [116:64]
    // Guard bit (0.5权重):      位于 bit 63
    // Round bit (0.25权重):     位于 bit 62
    // Sticky bit (剩余所有):    位于 bit [61:0] 的 OR
    
    wire [52:0] rounder_mant_in = shifted_mant[116:64];
    wire        rounder_g       = shifted_mant[63];
    wire        rounder_r       = shifted_mant[62];
    wire        rounder_s       = |shifted_mant[61:0];

    // =========================================================================
    // 3. 实例化舍入模块 (fp_rounder)
    // =========================================================================
    wire [52:0] rounder_mant_out;
    wire        rounder_carry;

    // 这里复用 fp_rounder。虽然它是为浮点尾数设计的，但其逻辑:
    // "若满足舍入条件则加1" 对整数转换同样适用。
    fp_rounder u_rounder (
        .mant_in     (rounder_mant_in),
        .g           (rounder_g),
        .r           (rounder_r),
        .s           (rounder_s),
        .mant_out    (rounder_mant_out),
        .carry_out   (rounder_carry)
    );

    // 组合舍入后的绝对值 (针对 Exp <= 52 的情况)
    // 结果 = {进位, 舍入后的53位}
    wire [53:0] abs_int_small = {rounder_carry, rounder_mant_out};

    // =========================================================================
    // 4. 大数处理 (Exp > 52) 与 结果选择
    // =========================================================================
    
    // int64 最大正整数 2^63 - 1。
    // 如果 exp > 52，我们需要左移还原整数。
    // 这里的 shift 是 exponent - 52。
    
    reg [63:0] abs_int_large;
    always @(*) begin
        // 限制左移位宽防止仿真报错，实际溢出会由后续逻辑处理
        if (exponent > 52 && exponent < 116) begin
            abs_int_large = {11'b0, mantissa} << (exponent - 52);
        end else begin
            // 极大溢出，设为全1方便后续饱和处理
            abs_int_large = 64'hFFFF_FFFF_FFFF_FFFF; 
        end
    end

    // 综合绝对值
    reg [63:0] abs_result;
    always @(*) begin
        if (exponent > 52) begin
            abs_result = abs_int_large;
        end else begin
            // 高位补0
            abs_result = {10'b0, abs_int_small}; 
        end
    end

    // =========================================================================
    // 5. 符号处理与溢出饱和 (Saturation)
    // =========================================================================
    
    localparam [63:0] MAX_INT = 64'h7FFF_FFFF_FFFF_FFFF; //  9223372036854775807
    localparam [63:0] MIN_INT = 64'h8000_0000_0000_0000; // -9223372036854775808

    always @(*) begin
        if (is_nan) begin
            int_out = 64'd0;
        end
        else if (is_inf) begin
            int_out = sign ? MIN_INT : MAX_INT;
        end
        else begin
            // 检查溢出
            // 1. Exp >= 63: 肯定溢出 (除了 -2^63 这个特例)
            // 2. Exp < 63: 需要检查计算出的 abs_result 是否越界
            
            if (exponent >= 63) begin
                // 特例: -2^63 (exp=63, mant=1.0)
                // 注意 mantissa 包含隐藏位，如果是 1.0...0，mantissa 值为 53'h10_0000...
                // 但这里 mantissa 信号来自 decomposer，如果是规格化数，它是 {1, raw}
                // 精确的 2^63 浮点数: Exponent 63, Mantissa 1.0
                if (sign && exponent == 63 && mantissa == 53'h10_0000_0000_0000) begin
                    int_out = MIN_INT; // 合法
                end else begin
                    int_out = sign ? MIN_INT : MAX_INT; // 饱和
                end
            end
            else begin
                // Exponent <= 62
                // 此时 abs_result 最大可能为 2^63 (如果 Exp=62 且发生进位，或者 Exp=62 Mantissa大)
                // 检查位 63
                if (abs_result[63]) begin
                    // 绝对值 >= 2^63
                    // 只有 -2^63 是合法的
                    if (sign && abs_result == MIN_INT) begin // abs_result == 2^63 (as unsigned 0x8000...)
                        int_out = MIN_INT;
                    end else begin
                        // 正数溢出 或 负数超过 -2^63
                        int_out = sign ? MIN_INT : MAX_INT;
                    end
                end 
                else begin
                    // 正常范围
                    int_out = sign ? -abs_result : abs_result;
                end
            end
        end
    end

endmodule
`default_nettype wire
