// src/fp_add_sub.v
// 功能：实现IEEE 754双精度浮点数的加法和减法
// 依赖子模块：fp_decomposer, alignment_shifter, add_sub_53, lzc_53, fp_rounder, fp_recomposer

`default_nettype none

module fp_add_sub (
    input  wire [63:0] fp_a_in,   // 操作数A
    input  wire [63:0] fp_b_in,   // 操作数B
    input  wire        is_sub,    // 1'b1: 减法 (A-B), 1'b0: 加法 (A+B)

    output wire [63:0] fp_res_out // 结果
);

    // --- 阶段 1: 分解与特殊值检查 ---
    wire        sign_a, sign_b;
    wire [11:0] exp_a, exp_b;
    wire [52:0] mant_a, mant_b;
    wire        is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;
    wire        is_denorm_a, is_denorm_b;

    fp_decomposer decomposer_a (
        .fp_in(fp_a_in), 
        .sign(sign_a), 
        .exponent(exp_a), 
        .mantissa(mant_a),
        .is_nan(is_nan_a), 
        .is_inf(is_inf_a), 
        .is_zero(is_zero_a), 
        .is_denormalized(is_denorm_a)
    );

    fp_decomposer decomposer_b (
        .fp_in(fp_b_in), 
        .sign(sign_b), 
        .exponent(exp_b), 
        .mantissa(mant_b),
        .is_nan(is_nan_b), 
        .is_inf(is_inf_b), 
        .is_zero(is_zero_b), 
        .is_denormalized(is_denorm_b)
    );

    // 有效操作判断 (符号不同做减法, 符号相同做加法)
    //1减0加
    wire effective_sub = is_sub ^ sign_a ^ sign_b;

    // 特殊情况处理
    wire res_is_nan = is_nan_a || is_nan_b || (is_inf_a && is_inf_b && effective_sub);
    wire res_is_inf = (is_inf_a || is_inf_b) && !(is_inf_a && is_inf_b && effective_sub);
    wire inf_sign = (is_inf_a) ? sign_a : sign_b;

    reg [63:0] special_case_res;
    wire        is_special_case;

    // 如果是特殊情况，直接输出结果，否则进入常规路径
    assign is_special_case = is_nan_a || is_nan_b || is_inf_a || is_inf_b || is_zero_a || is_zero_b;
    

    always @(*) begin
        // 默认值，可以设为0或一个特定的调试值
        special_case_res = 64'd0; 

        // --- NaN (Not a Number) 的处理 ---
        // 规则: 任何运算涉及到一个 NaN，结果都是 NaN。
        if (res_is_nan) begin
            // 输出一个 Quiet NaN (QNaN)。最高有效位为1。
            special_case_res = 64'h7FF8000000000001;
        end
        // --- 无穷大 (Infinity) 的处理 ---
        else if (res_is_inf) begin
            // 符号与无穷的符号相同
            special_case_res = {inf_sign, 11'h7FF, 52'h0};
        end
        // --- 零 (Zero) 的处理 ---
        else if (is_zero_a || is_zero_b) begin
            // 场景1: A 是 0
            // 0 + B = B
            // 0 - B = -B
            if (is_zero_a) begin
                // 当两个操作数都为0时，此逻辑也适用
                // +0 + (+0) = +0, -0 + (-0) = -0
                // +0 + (-0) = +0 (根据舍入模式，通常为+0)
                // +0 - (+0) = +0, +0 - (-0) = +0
                if (is_zero_b && (sign_a == (sign_b ^ is_sub))) begin
                    // 两个零相减且符号相同，或相加且符号相反，结果为+0
                    special_case_res = 64'h0000000000000000;
                end else begin
                    // is_sub 为真，对 B 的符号位取反
                    special_case_res = {(sign_b ^ is_sub), fp_b_in[62:0]};
                end
            end
            // 场景2: B 是 0 (且 A 不是 0)
            // A +/- 0 = A
            else begin // is_zero_b
                special_case_res = fp_a_in;
            end
        end
    end



    

    // --- 常规路径：两个数都是规格化/非规格化数 ---

    // --- 阶段 2: 对阶 ---
    wire [11:0] exp_diff;
    wire a_exp_is_larger = (exp_a > exp_b);

    wire [11:0] exp_large = a_exp_is_larger ? exp_a : exp_b;
    wire [11:0] exp_small = a_exp_is_larger ? exp_b : exp_a;

    wire [52:0] mant_large = a_exp_is_larger ? mant_a : mant_b;
    wire [52:0] mant_small = a_exp_is_larger ? mant_b : mant_a;
    wire        sign_large = a_exp_is_larger ? sign_a : sign_b;

    assign exp_diff = exp_large - exp_small;

    // 对阶移位
    wire [52:0] mant_small_shifted;
    wire        g, r, s;

    // 如果指数差过大，小数值对结果无影响
    // G,R,S 也会被正确处理为0
    wire huge_diff = (exp_diff > 54);

    alignment_shifter shifter (
        .mant_in(mant_small),
        .shift_amount(huge_diff ? 6'd63 : exp_diff[5:0]),
        .mant_out(mant_small_shifted),
        .g_out(g),
        .r_out(r),
        .s_out(s)
    );

    // --- 阶段 3: 尾数加/减 ---
    wire [53:0] add_sub_res;
    add_sub_53 adder (
        .a(mant_large),
        .b(mant_small_shifted),
        .is_sub(effective_sub),
        .result(add_sub_res)
    );

    wire res_sign = sign_large; // 结果的符号初步判断为较大数的符号

    // --- 阶段 4: 规格化 ---
    wire        add_overflow = add_sub_res[53] && !effective_sub; // 加法溢出，最高位是2
    wire        sub_cancel   = !add_sub_res[52] && effective_sub; // 减法抵消，最高位是0
    wire [5:0]  lzc_amount;

    lzc_53 lzc (.data_in(add_sub_res[52:0]), .count(lzc_amount));

    reg [11:0] norm_exp;
    reg [52:0] norm_mant;
    reg         norm_g, norm_r, norm_s;

    // 根据情况选择规格化操作
    always @(*) begin
        if (add_overflow) begin // 加法溢出, 右移1位, 指数+1
            norm_exp  = exp_large + 1;
            norm_mant = add_sub_res[53:1];
            norm_g    = add_sub_res[0]; // 新的G是原结果的LSB
            norm_r    = g;              // 新的R是原来的G
            norm_s    = r | s;          // 新的S是原来R和S的或
        end else if (sub_cancel) begin // 减法抵消, 左移
            norm_exp = exp_large - lzc_amount;
            {norm_mant, norm_g, norm_r, norm_s} = {add_sub_res[52:0], g, r, s} << lzc_amount;
        end else begin // 无需规格化
            norm_exp  = exp_large;
            norm_mant = add_sub_res[52:0];
            norm_g    = g;
            norm_r    = r;
            norm_s    = s;
        end

    end

    // --- 阶段 5: 舍入 ---
    wire [52:0] rounded_mant;
    wire        round_carry_out;

    fp_rounder rounder (
        .mant_in(norm_mant),
        .g(norm_g), .r(norm_r), .s(norm_s),
        .mant_out(rounded_mant),
        .carry_out(round_carry_out)
    );

    // --- 阶段 6 & 7: 最终组合 ---
    wire [11:0] final_exp;
    wire [52:0] final_mant;
    
    // 检查舍入是否再次导致溢出
    assign final_exp  = round_carry_out ? (norm_exp + 1) : norm_exp;
    assign final_mant = round_carry_out ? 53'h10000000000000 : rounded_mant; // 溢出后尾数为1.000...

    // 判断最终结果是否为0 (减法完全抵消)
    // 如果规格化后的尾数是0，则结果是0
    wire final_is_zero = (norm_mant == 0); 

    wire [63:0] normal_path_res;
    fp_recomposer recomposer (
        .final_sign(res_sign),
        .final_exponent(final_exp),
        .final_mantissa(final_mant),
        .is_nan_out(1'b0), // NaN在特殊路径处理
        .is_inf_out(1'b0), // Inf在特殊路径处理
        .is_zero_out(final_is_zero),
        .fp_out(normal_path_res)
    );

    // --- 最终输出选择 ---
    assign fp_res_out = is_special_case ? special_case_res : normal_path_res;

endmodule

`default_nettype wire
