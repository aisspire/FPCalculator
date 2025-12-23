// src/fp_add_sub.v
// 功能：实现IEEE 754双精度浮点数(64-bit)的加法和减法
// 核心逻辑：
// 1. 拆解浮点数，提取符号、指数、尾数（含隐藏位）
// 2. 特殊值检查 (NaN, Inf, Zero)
// 3. 对阶：小阶向大阶看齐，小阶尾数右移
// 4. 尾数运算：执行定点加减法
// 5. 规格化：处理溢出(右移)或消去(左移)，调整指数
// 6. 下溢处理：处理非规格化数 (Denormal)
// 7. 舍入：基于GRS位进行舍入
// 8. 打包：组合最终结果

`default_nettype none

module fp_add_sub (
    input  wire [63:0] fp_a_in,   // 操作数 A (IEEE 754 double)
    input  wire [63:0] fp_b_in,   // 操作数 B (IEEE 754 double)
    input  wire        is_sub,    // 操作码: 1'b1 为减法 (A-B), 1'b0 为加法 (A+B)

    output wire [63:0] fp_res_out // 运算结果
);

    // =========================================================================
    // 阶段 1: 解包与特殊值检测 (Decomposition & Special Check)
    // =========================================================================
    wire        sign_a, sign_b;
    wire signed [11:0] exp_a, exp_b; // 扩展到12位以处理溢出计算
    wire [52:0] mant_a, mant_b;      // 包含隐藏位 (1.xxxxx 或 0.xxxxx)
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

    // 确定有效操作类型
    // effective_sub = 1 表示做尾数减法，0 表示做尾数加法
    // 逻辑：用户指令(is_sub) XOR 符号A XOR 符号B
    // 例：(+A) - (-B) -> 等同于加法，is_sub=1, sign_a=0, sign_b=1 -> result=0 (加法)
    wire effective_sub = is_sub ^ sign_a ^ sign_b;

    // =========================================================================
    // 特殊情况逻辑 (NaN, Inf, Zero)
    // =========================================================================
    // 任何操作数为NaN，结果为NaN；同号无穷大相减(Inf-Inf)也是NaN
    wire res_is_nan = is_nan_a || is_nan_b || (is_inf_a && is_inf_b && effective_sub);
    // 任意操作数为Inf(且非Inf-Inf情况)，结果为Inf
    wire res_is_inf = (is_inf_a || is_inf_b) && !(is_inf_a && is_inf_b && effective_sub);
    // 确定无穷大结果的符号
    wire inf_sign = (is_inf_a) ? sign_a : sign_b;

    reg [63:0] special_case_res;
    wire       is_special_case;

    // 只要有 NaN, Inf 或 Zero 参与，就进入特殊处理路径
    assign is_special_case = is_nan_a || is_nan_b || is_inf_a || is_inf_b || is_zero_a || is_zero_b;
    
    always @(*) begin
        special_case_res = 64'd0; 

        // --- 优先级 1: NaN (Not a Number) ---
        if (res_is_nan) begin
            // 返回标准 QNaN (Quiet NaN)
            special_case_res = 64'h7FF8000000000000;
        end
        // --- 优先级 2: 无穷大 (Infinity) ---
        else if (res_is_inf) begin
            special_case_res = {inf_sign, 11'h7FF, 52'h0};
        end
        // --- 优先级 3: 两个数都是 0 ---
        else if (is_zero_a && is_zero_b) begin
            if (effective_sub) begin
                // 同号相减或异号相加导致 0 的情况，IEEE 754 规定结果为 +0
                // (除非舍入模式是向负无穷，此处假设默认舍入模式)
                special_case_res = 64'h0000000000000000; 
            end else begin
                // 同号 0 相加，符号跟随操作数 (如 -0 + -0 = -0)
                special_case_res = fp_a_in; 
            end
        end
        // --- 优先级 4: 仅 A 为 0 ---
        else if (is_zero_a) begin 
            // 0 +/- B -> 结果由 B 决定，需注意减法时的符号翻转
            special_case_res = {(sign_b ^ is_sub), fp_b_in[62:0]}; 
        end
        // --- 优先级 5: 仅 B 为 0 ---
        else begin // is_zero_b
            // A +/- 0 -> 结果为 A
            special_case_res = fp_a_in; 
        end
    end

    // =========================================================================
    // 常规路径 (Normal Path)
    // =========================================================================

    // --- 阶段 2: 对阶 (Alignment) ---
    // 找出绝对值较大的数(Large)和较小的数(Small)，以大数指数为基准
    wire signed [11:0] exp_diff;
    // 比较逻辑：指数大者大；指数相同则尾数大者大
    wire op_a_is_larger = (exp_a > exp_b) || ((exp_a == exp_b) && (mant_a >= mant_b));

    wire signed [11:0] exp_large = op_a_is_larger ? exp_a : exp_b;
    wire signed [11:0] exp_small = op_a_is_larger ? exp_b : exp_a;

    wire [52:0] mant_large = op_a_is_larger ? mant_a : mant_b;
    wire [52:0] mant_small = op_a_is_larger ? mant_b : mant_a;

    assign  exp_diff = exp_large - exp_small;

    // 移位逻辑：将小数的尾数右移，以对齐大数的指数
    wire [52:0] mant_small_shifted;
    wire        g, r, s; // Guard, Round, Sticky bits 用于精度保护

    // 如果指数差 > 54，小数的有效位已经完全移出，只保留Sticky位的影响
    wire huge_diff = (exp_diff > 54);

    alignment_shifter shifter (
        .mant_in(mant_small),
        .shift_amount(huge_diff ? 6'd63 : exp_diff[5:0]),
        .mant_out(mant_small_shifted),
        .g_out(g),
        .r_out(r),
        .s_out(s)
    );

    // --- 阶段 3: 尾数加/减运算 (Mantissa Add/Sub) ---
    wire [53:0] add_sub_res; // 54位宽：52bit尾数 + 1bit隐藏位 + 1bit溢出位
    add_sub_53 adder (
        .a(mant_large),
        .b(mant_small_shifted),
        .is_sub(effective_sub),
        .result(add_sub_res)
    );

    // 确定暂定结果的符号
    // 如果是减法，且A>B，符号随A；若A<B，符号为B的翻转；若A=B，结果为0（由后续逻辑处理）
    wire sign_b_eff = sign_b ^ is_sub;
    wire res_sign = effective_sub ? (op_a_is_larger ? sign_a : sign_b_eff) : sign_a;

    // --- 阶段 4: 规格化 (Normalization) ---
    wire        add_overflow = add_sub_res[53] && !effective_sub; // 加法进位 (1.x + 1.x = 1x.x)
    wire        sub_cancel   = !add_sub_res[52] && effective_sub; // 减法借位消去 (1.x - 0.9x = 0.0x)
    wire [5:0]  lzc_amount;

    // LZC 计算前导零个数，用于减法严重消去后的左移恢复
    lzc_53 lzc (.data_in(add_sub_res[52:0]), .count(lzc_amount));

    reg signed [11:0] norm_exp;
    reg [52:0] norm_mant;
    reg         norm_g, norm_r, norm_s;

    always @(*) begin
        if (add_overflow) begin 
            // 尾数溢出 (e.g., 1x.xxx)，右移1位，指数+1
            norm_exp  = exp_large + 1;
            norm_mant = add_sub_res[53:1];
            norm_g    = add_sub_res[0]; // 最低位变成新的 G 位
            norm_r    = g;              // 原 G 位变成 R 位
            norm_s    = r | s;          // 剩余位合并入 Sticky
        end else if (sub_cancel) begin 
            // 尾数消去 (e.g., 0.001xx)，左移 N 位，指数-N
            norm_exp = exp_large - lzc_amount;
            // 左移并将 GRS 位补入低位
            {norm_mant, norm_g, norm_r, norm_s} = {add_sub_res[52:0], g, r, s} << lzc_amount;
        end else begin 
            // 无需移动
            norm_exp  = exp_large;
            norm_mant = add_sub_res[52:0];
            norm_g    = g;
            norm_r    = r;
            norm_s    = s;
        end
    end

    // --- 阶段 5: 下溢判断与预处理 (Underflow Handling) ---
    // 检查规格化后的指数是否过小 (小于最小规格化指数 -1022)
    localparam signed MIN_EXP = -1022;
    wire        is_underflow_candidate = (norm_exp < MIN_EXP);
    wire [11:0] shift_amount_uf = MIN_EXP - norm_exp; // 计算需要右移多少位变回非规格化数

    reg signed  [52:0] pre_round_mant;
    reg signed [11:0] pre_round_exp;
    reg        pre_round_g, pre_round_r, pre_round_s;

    always @(*) begin
        if (is_underflow_candidate && (shift_amount_uf < 54)) begin
            // 发生下溢，强制将指数设为 MIN_EXP，并将尾数右移 (变为 0.xxxx 的非规格化形式)
            pre_round_exp = MIN_EXP;
            // 注意：右移时要补入 1'b0 (因为 norm_mant 此时是隐含 1 的规格化数)
            {pre_round_mant, pre_round_g, pre_round_r, pre_round_s} = 
                {{1'b0, norm_mant}, norm_g, norm_r, norm_s} >> shift_amount_uf;
        end else begin
            // 正常范围，或下溢严重导致完全归零
            pre_round_exp  = norm_exp;
            pre_round_mant = norm_mant;
            pre_round_g    = norm_g;
            pre_round_r    = norm_r;
            pre_round_s    = norm_s;
        end
    end

    // --- 阶段 6: 舍入 (Rounding) ---
    wire [52:0] rounded_mant;
    wire        round_carry_out; // 舍入可能导致再次进位 (e.g., 1.11...1 + 1 -> 10.0...0)

    fp_rounder rounder (
        .mant_in(pre_round_mant),
        .g(pre_round_g), .r(pre_round_r), .s(pre_round_s),
        .mant_out(rounded_mant),
        .carry_out(round_carry_out)
    );

    // --- 阶段 7: 最终组合与打包 (Final Composition) ---
    reg [11:0] final_exp_field;
    reg [51:0] final_mant_field;
    
    // 判断结果是否为绝对零 (减法完全抵消 或 下溢且舍入后为0)
    wire final_is_zero = (rounded_mant == 0); 
    
    always@(*) begin
        // 初始化默认值
        final_exp_field  = 12'd0;
        final_mant_field = 52'd0;

        if (round_carry_out) begin
            // === 情况 A: 舍入导致进位 ===
            if (pre_round_exp == 1023) begin 
                // 最大规格化数进位 -> 溢出为无穷大
                final_exp_field = 11'h7FF;
                final_mant_field = 52'h0;
            end else if (pre_round_exp == MIN_EXP - 1) begin 
                // 最大非规格化数进位 -> 变为最小规格化数
                final_exp_field = 1;      // 指数位为 1
                final_mant_field = 52'h0; // 尾数全 0
            end else begin
                // 普通进位，指数 + 1
                final_exp_field = pre_round_exp + 1023 + 1; // 加上偏置值 1023
                final_mant_field = 52'h0; 
            end
        end else begin
            // === 情况 B: 无舍入进位 ===
            // 区分规格化数与非规格化数
            // 如果指数 < -1022，或指数为 -1022 但最高位是 0 (非规格化)
            if (pre_round_exp < MIN_EXP || (pre_round_exp == MIN_EXP && rounded_mant[52] == 0)) begin
                // 非规格化数：指数域填 0，尾数直接填入
                final_exp_field = 11'h000;
                final_mant_field = rounded_mant[51:0];
            end else begin 
                // 规格化数：指数域 = 真实指数 + 1023，尾数丢弃隐藏位
                final_exp_field = pre_round_exp + 1023;
                final_mant_field = rounded_mant[51:0]; 
            end
        end
        
        // 最后检查：如果指数逻辑上超过了最大值 (上溢)
        if (norm_exp > 1023) begin
            final_exp_field = 11'h7FF;
            final_mant_field = 52'h0;
        end
    end

    wire [63:0] normal_path_res;
    // 重组器：将符号、计算出的指数域和尾数域拼成 64-bit 浮点数
    fp_recomposer recomposer (
        .final_sign(res_sign),
        .final_exponent_field(final_exp_field[10:0]),
        .final_mantissa_field(final_mant_field),
        .is_nan_out(1'b0), // NaN 已在特殊路径处理
        .is_inf_out(norm_exp > 1023 || (round_carry_out && pre_round_exp == 1023)), 
        .is_zero_out(final_is_zero),
        .fp_out(normal_path_res)
    );

    // --- 最终输出选择 ---
    // 如果触发特殊情况(NaN/Inf/Zero)，输出特殊值；否则输出计算结果
    assign fp_res_out = is_special_case ? special_case_res : normal_path_res;

endmodule
`default_nettype wire
