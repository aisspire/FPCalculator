// src/common/fp_decomposer.v
// 功能：将64位双精度浮点数分解为符号、指数、尾数及特殊标志位

`default_nettype none

module fp_decomposer (
    input  wire [63:0] fp_in,          // 输入的64位浮点数

    output wire        sign,           // 符号位
    output wire signed [11:0] exponent,       // 12位指数 (含符号，为方便计算)
    output wire [52:0] mantissa,       // 53位尾数 (规格化数含隐藏位'1', 非规格化数含'0')
    
    output wire        is_nan,         // 是不是NaN
    output wire        is_inf,         // 是不是无穷大
    output wire        is_zero,        // 是不是零
    output wire        is_denormalized // 是不是非规格化数
);

    // 1. 直接从输入中拆分字段
    wire        raw_sign      = fp_in[63];
    wire [10:0] raw_exponent  = fp_in[62:52];
    wire [51:0] raw_mantissa  = fp_in[51:0];

    // 2. 定义特殊指数值
    localparam EXP_ALL_ZEROS = 11'h000;
    localparam EXP_ALL_ONES  = 11'h7FF;
    localparam signed [12:0] EXP_BIAS = 13'sd1023;

    // 3. 判断特殊类型
    wire is_special_exp = (raw_exponent == EXP_ALL_ZEROS) || (raw_exponent == EXP_ALL_ONES);
    wire is_mantissa_zero = (raw_mantissa == 52'h0);

    // is_nan: exp全1, mantissa非0. [3, 4]
    assign is_nan = (raw_exponent == EXP_ALL_ONES) && (!is_mantissa_zero);
    
    // is_inf: exp全1, mantissa为0. [3, 4]
    assign is_inf = (raw_exponent == EXP_ALL_ONES) && (is_mantissa_zero);
    
    // is_zero: exp全0, mantissa为0. [4]
    assign is_zero = (raw_exponent == EXP_ALL_ZEROS) && (is_mantissa_zero);
    
    // is_denormalized: exp全0, mantissa非0. [4]
    assign is_denormalized = (raw_exponent == EXP_ALL_ZEROS) && (!is_mantissa_zero);

    // 4. 计算输出
    assign sign = raw_sign;

    // 指数计算：
    // - 规格化数: 实际指数 = 偏移指数 - 偏移量
    // - 非规格化数: 实际指数固定为 1 - 偏移量 = -1022
    // - 特殊值: 指数可以设为0，因为会被is_nan/is_inf标志处理
    assign exponent = (is_denormalized) ? (13'sd1 - EXP_BIAS) :          // 非规格化数，指数为 1-1023 = -1022
                    (is_special_exp)  ? 12'sd0 :                  // 特殊值 (Inf, NaN)，指数可为0
                                      ($signed({2'b0, raw_exponent}) - EXP_BIAS); // 规格化数


    // 尾数计算：
    // - 规格化数: 尾数 = {1'b1, raw_mantissa}
    // - 非规格化数: 尾数 = {1'b0, raw_mantissa}
    // - 特殊值(0, inf, nan): 尾数可以为0，由标志位处理
    assign mantissa = (is_denormalized) ? {1'b0, raw_mantissa} : 
                      (is_special_exp) ? 53'd0 : 
                                         {1'b1, raw_mantissa};            
endmodule

`default_nettype wire

