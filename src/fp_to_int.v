`default_nettype none

// =========================================================================
// 模块名称: fp_to_int
// 功能描述: 将 64位双精度浮点数 (IEEE 754) 转换为 64位有符号整数。
//          支持舍入模式（通过 fp_rounder 实现，通常为最近偶数舍入），
//          并处理 NaN、Infinity 以及整数溢出的饱和截断。
// =========================================================================
module fp_to_int (
    input  wire [63:0] fp_in,   // 输入浮点数
    output reg  [63:0] int_out  // 输出 64位有符号整数
);

    // =========================================================================
    // 1. 浮点数拆解 (Decomposition)
    // =========================================================================
    wire        sign;           // 符号位 (1为负)
    wire signed [11:0] exponent; // 无偏指数 (实际指数值)
    wire [52:0] mantissa;       // 尾数 (包含隐藏位 1.x)
    wire        is_nan;         // 非数标志
    wire        is_inf;         // 无穷大标志
    
    // 实例化拆解模块，提取 IEEE 754 的各个分量
    fp_decomposer u_decomposer (
        .fp_in           (fp_in),
        .sign            (sign),
        .exponent        (exponent),
        .mantissa        (mantissa),
        .is_nan          (is_nan),
        .is_inf          (is_inf),
        .is_zero         (), // 零在后续逻辑中自然处理，无需显式信号
        .is_denormalized ()  // 非规格化数在整数转换中通常视为极小值处理
    );

    // =========================================================================
    // 2. 小数对齐与舍入位提取 (Alignment & Pre-rounding)
    // -------------------------------------------------------------------------
    // 逻辑说明:
    // 当 exponent <= 52 时，浮点数包含小数部分，需要进行舍入。
    // 我们通过右移操作将二进制点对齐，从而分离出整数部分和用于舍入的 G/R/S 位。
    // =========================================================================
    
    reg [6:0]   r_shift_amt;    // 右移位数
    reg [116:0] shifted_mant;   // 扩展后的尾数移位寄存器 ({mantissa, 64'b0})
    
    always @(*) begin
        // 计算右移量：目的是将目标整数的 LSB 对齐到特定的 bit 位
        if (exponent <= 52 && exponent >= -60) begin 
            // 正常范围：尾数跨越整数和小数部分
            // Shift = 52 - Exp。Exp=52时不移位(全整数)，Exp=0时右移52位(全小数)
            r_shift_amt = 7'd52 - exponent[6:0]; 
        end else if (exponent < -60) begin
            // 极小值处理：指数极小，数值远小于0.5，全部移出成为 Sticky 位
            r_shift_amt = 7'd116; 
        end else begin
            // 大数处理 (Exp > 52)：无小数部分，不需要此处的右移逻辑
            r_shift_amt = 7'd0;
        end
        
        // 执行移位：高位是原始尾数，低位补0，右移后低位即为小数部分
        shifted_mant = {mantissa, 64'b0} >> r_shift_amt;
    end

    // 从移位结果中提取用于 Rounder 模块的信号
    // [116:64] 为整数部分 (53位)，[63]为Guard，[62]为Round，[61:0]聚合为Sticky
    wire [52:0] rounder_mant_in = shifted_mant[116:64];
    wire        rounder_g       = shifted_mant[63];      // 0.5 权重位
    wire        rounder_r       = shifted_mant[62];      // 0.25 权重位
    wire        rounder_s       = |shifted_mant[61:0];   // 剩余所有低位的逻辑或

    // =========================================================================
    // 3. 舍入处理 (Rounding)
    // =========================================================================
    wire [52:0] rounder_mant_out;
    wire        rounder_carry;

    // 复用通用舍入模块，根据 G, R, S 位决定是否向整数部分进位
    fp_rounder u_rounder (
        .mant_in     (rounder_mant_in),
        .g           (rounder_g),
        .r           (rounder_r),
        .s           (rounder_s),
        .mant_out    (rounder_mant_out), // 舍入后的整数尾数
        .carry_out   (rounder_carry)     // 舍入产生的进位
    );

    // 组合舍入后的小数部分转换结果 (针对 Exp <= 52)
    // 结果形式为 {进位, 尾数}，构成 54 位整数绝对值
    wire [53:0] abs_int_small = {rounder_carry, rounder_mant_out};

    // =========================================================================
    // 4. 大数处理与结果选择 (Large Number Handling)
    // -------------------------------------------------------------------------
    // 当 exponent > 52 时，数值很大且无小数部分，直接左移还原整数值。
    // =========================================================================
    
    reg [63:0] abs_int_large;
    
    always @(*) begin
        // 左移还原：实际数值 = Mantissa * 2^(Exp - 52)
        // 限制左移范围 < 116 是为了防止仿真器警告，实际溢出由后续逻辑通过 Exp 判断
        if (exponent > 52 && exponent < 116) begin
            abs_int_large = {11'b0, mantissa} << (exponent - 52);
        end else begin
            // 极大值溢出保护 (设为全1，后续逻辑会截断)
            abs_int_large = 64'hFFFF_FFFF_FFFF_FFFF; 
        end
    end

    // 根据指数范围选择最终的绝对值结果
    reg [63:0] abs_result;
    always @(*) begin
        if (exponent > 52) begin
            abs_result = abs_int_large;
        end else begin
            // 小数模式：高位补零，低位接舍入后的结果
            abs_result = {10'b0, abs_int_small}; 
        end
    end

    // =========================================================================
    // 5. 符号应用与饱和截断 (Sign application & Saturation)
    // =========================================================================
    
    // 64位有符号整数的极值定义
    localparam [63:0] MAX_INT = 64'h7FFF_FFFF_FFFF_FFFF; //  (2^63 - 1)
    localparam [63:0] MIN_INT = 64'h8000_0000_0000_0000; // (-2^63)

    always @(*) begin
        if (is_nan) begin
            int_out = 64'd0; // IEEE 754 标准通常规定 NaN 转整数为 0 (具体依赖架构)
        end
        else if (is_inf) begin
            int_out = sign ? MIN_INT : MAX_INT; // 无穷大 -> 饱和到极值
        end
        else begin
            // --- 溢出检查逻辑 ---
            
            // 情况 1: 指数 >= 63，绝对值肯定 >= 2^63
            // 唯一的例外是 -2^63 (Exp=63, Mantissa=1.0, Sign=1)
            if (exponent >= 63) begin
                // 检查是否为 -2^63 的精确表示 (mantissa 53'h10... 代表 1.0)
                if (sign && exponent == 63 && mantissa == 53'h10_0000_0000_0000) begin
                    int_out = MIN_INT; // 合法最小值
                end else begin
                    int_out = sign ? MIN_INT : MAX_INT; // 否则均为溢出，饱和处理
                end
            end
            // 情况 2: 指数 <= 62，但计算出的绝对值可能触及边界
            else begin
                // 检查 bit 63。如果置位，说明绝对值 >= 2^63 (当作无符号看)
                // 在有符号数中，只有 -2^63 (0x8000...) 是合法的，+2^63 溢出。
                if (abs_result[63]) begin
                    if (sign && abs_result == MIN_INT) begin 
                        int_out = MIN_INT; // 刚好是 -2^63，合法
                    end else begin
                        int_out = sign ? MIN_INT : MAX_INT; // 溢出饱和
                    end
                end 
                else begin
                    // 正常范围：应用符号位
                    int_out = sign ? -abs_result : abs_result;
                end
            end
        end
    end

endmodule
`default_nettype wire
