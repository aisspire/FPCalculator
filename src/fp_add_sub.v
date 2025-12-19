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
    wire signed [11:0] exp_a, exp_b;
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
            special_case_res = 64'h7FF8000000000000;
        end
        // --- 无穷大 (Infinity) 的处理 ---
        else if (res_is_inf) begin
            // 符号与无穷的符号相同
            special_case_res = {inf_sign, 11'h7FF, 52'h0};
        end
        // --- 零 (Zero) 的处理 ---
        else if (is_zero_a && is_zero_b) begin
            // effective_sub = is_sub ^ sign_a ^ sign_b
            // 如果是有效减法 (例如 (+0)+(-0) 或 (+0)-(+0))，结果是 +0
            if (effective_sub) begin
                special_case_res = 64'h0000000000000000; // +0
            end else begin
                // 否则是有效加法 (例如 (+0)+(+0) 或 (-0)+(-0))，结果符号不变
                // 两个操作数都是0，取哪个都一样
                special_case_res = fp_a_in;
            end
        end
        else if (is_zero_a) begin // 只有 A 是 0
            special_case_res = {(sign_b ^ is_sub), fp_b_in[62:0]}; // 0 +/- B = +/-B
        end
        else begin // 只有 B 是 0
            special_case_res = fp_a_in; // A +/- 0 = A
        end
    end



    

    // --- 常规路径：两个数都是规格化/非规格化数 ---

    // --- 阶段 2: 对阶 ---
    wire signed [11:0] exp_diff;
    wire op_a_is_larger = (exp_a > exp_b) || ((exp_a == exp_b) && (mant_a >= mant_b));

    wire signed [11:0] exp_large = op_a_is_larger ? exp_a : exp_b;
    wire signed [11:0] exp_small = op_a_is_larger ? exp_b : exp_a;

    wire [52:0] mant_large = op_a_is_larger ? mant_a : mant_b;
    wire [52:0] mant_small = op_a_is_larger ? mant_b : mant_a;

    assign  exp_diff = exp_large - exp_small;

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

    wire sign_b_eff = sign_b ^ is_sub;
    wire res_sign = effective_sub ? (op_a_is_larger ? sign_a : sign_b_eff) : sign_a;

    // --- 阶段 4: 规格化 ---
    wire        add_overflow = add_sub_res[53] && !effective_sub; // 加法溢出，最高位是2
    wire        sub_cancel   = !add_sub_res[52] && effective_sub; // 减法抵消，最高位是0
    wire [5:0]  lzc_amount;

    lzc_53 lzc (.data_in(add_sub_res[52:0]), .count(lzc_amount));

    reg signed [11:0] norm_exp;
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

    // --- 阶段 5: 下溢判断与预处理 ---
    // 在这里，我们需要处理从规格化阶段来的 norm_exp, norm_mant, 和 g,r,s 位
    // 检查指数是否小于最小规格化指数 (-1022)
    localparam signed MIN_EXP = -1022;
    wire        is_underflow_candidate = (norm_exp < MIN_EXP);
    wire [11:0] shift_amount_uf = MIN_EXP - norm_exp; // 计算需要右移的位数

    reg signed  [52:0] pre_round_mant;
    reg signed [11:0] pre_round_exp;
    reg        pre_round_g, pre_round_r, pre_round_s;

    always @(*) begin
        if (is_underflow_candidate && (shift_amount_uf < 54)) begin
            // 发生下溢，需要右移尾数，将其转为非规格化数形式
            pre_round_exp = MIN_EXP; // 准备进入非规格化范围
            // 将 norm_mant 和 g,r,s 拼接起来进行右移
            {pre_round_mant, pre_round_g, pre_round_r, pre_round_s} = 
                {{1'b0, norm_mant}, norm_g, norm_r, norm_s} >> shift_amount_uf;
        end else begin
            // 正常路径，或下溢后完全移出为0
            pre_round_exp  = norm_exp;
            pre_round_mant = norm_mant;
            pre_round_g    = norm_g;
            pre_round_r    = norm_r;
            pre_round_s    = norm_s;
        end
    end

    // --- 阶段 6: 舍入 ---
    wire [52:0] rounded_mant;
    wire        round_carry_out;

    fp_rounder rounder (
        .mant_in(pre_round_mant),
        .g(pre_round_g), .r(pre_round_r), .s(pre_round_s),
        .mant_out(rounded_mant),
        .carry_out(round_carry_out)
    );

    // --- 阶段 7: 最终组合 ---
    reg [11:0] final_exp_field;
    reg [51:0] final_mant_field;
    
    // 判断最终结果是否为0 (减法完全抵消或下溢为0)
    // rounded_mant全为0且无进位，则结果为0
    wire final_is_zero = (rounded_mant == 0); 
    
    reg temp_exp;
    
    always@(*) begin
        // 默认值
        final_exp_field  = 12'd0;
        final_mant_field = 52'd0;

        if (round_carry_out) begin
            // 舍入导致进位
            if (pre_round_exp == 1023) begin // 从最大规格化数溢出到无穷大
                final_exp_field = 11'h7FF;
                final_mant_field = 52'h0;
            end else if (pre_round_exp == MIN_EXP - 1) begin // 从非规格化数进位到规格化数
                final_exp_field = 1; // 最小的规格化指数
                final_mant_field = 52'h0; // 尾数部分为0
            end else begin
                final_exp_field = pre_round_exp + 1023 + 1;
                final_mant_field = 52'h0; // 尾数部分为0
            end
        end else begin
            // 无舍入进位
            // 如果指数小于-1022，或者指数等于-1022但隐藏位为0，则为非规格化数
            if (pre_round_exp < MIN_EXP || (pre_round_exp == MIN_EXP && rounded_mant[52] == 0)) begin
                final_exp_field = 11'h000;
                final_mant_field = rounded_mant[51:0];
            end else begin // 规格化数
                final_exp_field = pre_round_exp + 1023;
                final_mant_field = rounded_mant[51:0]; // 丢弃隐藏位
            end
        end
        
        // 检查指数上溢 (例如 norm_exp 本身就很大)
        if (norm_exp > 1023) begin
            final_exp_field = 11'h7FF;
            final_mant_field = 52'h0;
        end
    end


    wire [63:0] normal_path_res;
    fp_recomposer recomposer (
        .final_sign(res_sign),
        .final_exponent_field(final_exp_field[10:0]),
        .final_mantissa_field(final_mant_field),
        .is_nan_out(1'b0), // NaN在特殊路径处理
        .is_inf_out(norm_exp > 1023 || (round_carry_out && pre_round_exp == 1023)), // Inf
        .is_zero_out(final_is_zero),
        .fp_out(normal_path_res)
    );

    // --- 最终输出选择 ---
    assign fp_res_out = is_special_case ? special_case_res : normal_path_res;

endmodule
`default_nettype wire
