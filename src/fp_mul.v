// src/fp_mul.v
// 功能：实现IEEE 754双精度浮点数的乘法
// 依赖子模块：fp_decomposer, multiplier_53x53, fp_rounder, fp_recomposer

`default_nettype none

module fp_mul (
    input  wire [63:0] fp_a_in,   // 操作数A
    input  wire [63:0] fp_b_in,   // 操作数B

    output wire [63:0] fp_res_out // 结果
);

    // --- 阶段 1: 分解与特殊值检查 ---
    wire        sign_a, sign_b;
    wire [11:0] exp_a, exp_b;
    wire [52:0] mant_a, mant_b;
    wire        is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;

    fp_decomposer decomposer_a (
        .fp_in(fp_a_in), .sign(sign_a), .exponent(exp_a), .mantissa(mant_a),
        .is_nan(is_nan_a), .is_inf(is_inf_a), .is_zero(is_zero_a)
    );

    fp_decomposer decomposer_b (
        .fp_in(fp_b_in), .sign(sign_b), .exponent(exp_b), .mantissa(mant_b),
        .is_nan(is_nan_b), .is_inf(is_inf_b), .is_zero(is_zero_b)
    );
    
    wire res_sign = sign_a ^ sign_b;

    // 特殊情况处理
    // 0 * Inf = NaN
    wire zero_mul_inf = (is_zero_a && is_inf_b) || (is_inf_a && is_zero_b);
    
    wire res_is_nan  = is_nan_a || is_nan_b || zero_mul_inf;
    wire res_is_inf  = is_inf_a || is_inf_b; // 且不为 0*inf
    wire res_is_zero = is_zero_a || is_zero_b; // 且不为 0*inf

    wire is_special_case = res_is_nan || res_is_inf || res_is_zero;

    wire [63:0] special_case_res = res_is_nan  ? 64'h7FF8000000000001 : // NaN
                                   res_is_inf  ? {res_sign, 11'h7FF, 52'h0} : // Inf
                                   res_is_zero ? {res_sign, 11'h000, 52'h0} : // Zero
                                   64'd0; // Default

    // --- 常规路径 ---
    
    // --- 阶段 2: 核心计算 ---
    // 指数相加 (使用分解出的无偏指数)
    wire [11:0] sum_exp = exp_a + exp_b;

    // 尾数相乘
    wire [105:0] mant_product;
    multiplier_53x53 mant_multiplier (
        .a(mant_a),
        .b(mant_b),
        .product(mant_product)
    );
    
    // --- 阶段 3: 规格化 ---
    // 检查乘积是否溢出到第105位 (结果 >= 2.0)
    wire product_overflow = mant_product[105];

    wire [11:0] norm_exp;
    wire [52:0] norm_mant;
    wire        g, r, s;

    always @(*) begin
        if (product_overflow) begin // 结果 >= 2.0, 右移1位规格化
            norm_exp  = sum_exp + 1;
            norm_mant = mant_product[104:52];
            g         = mant_product[51];
            r         = mant_product[50];
            s         = |mant_product[49:0];
        end else begin // 结果在 [1.0, 2.0) 之间, 已规格化
            norm_exp  = sum_exp;
            norm_mant = mant_product[103:51];
            g         = mant_product[50];
            r         = mant_product[49];
            s         = |mant_product[48:0];
        end
    end

    // --- 阶段 4: 舍入 ---
    wire [52:0] rounded_mant;
    wire        round_carry_out;

    fp_rounder rounder (
        .mant_in(norm_mant),
        .g(g), .r(r), .s(s),
        .mant_out(rounded_mant),
        .carry_out(round_carry_out)
    );

    // --- 阶段 5: 最终组合 ---
    wire [11:0] final_exp;
    wire [52:0] final_mant;

    // 检查舍入是否再次导致溢出
    assign final_exp  = round_carry_out ? (norm_exp + 1) : norm_exp;
    assign final_mant = round_carry_out ? 53'h10000000000000 : rounded_mant;

    wire [63:0] normal_path_res;
    fp_recomposer recomposer (
        .final_sign(res_sign),
        .final_exponent(final_exp),
        .final_mantissa(final_mant),
        .is_nan_out(1'b0),
        .is_inf_out(1'b0),
        .is_zero_out(1'b0), // Zero在特殊路径处理
        .fp_out(normal_path_res)
    );

    // --- 最终输出选择 ---
    assign fp_res_out = is_special_case ? special_case_res : normal_path_res;

endmodule

`default_nettype wire
