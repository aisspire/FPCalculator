`default_nettype none

// ============================================================================
// 模块名称: fp_div
// 功能描述: 64位双精度浮点数除法器 (IEEE 754 标准)
//          支持非规约数、NaN、Infinity、Zero 的特殊情况处理。
//          包含 除法迭代、规格化、舍入 以及 结果重组。
// ============================================================================
module fp_div (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,      // 开始信号
    input  wire [63:0] fp_a,       // 被除数
    input  wire [63:0] fp_b,       // 除数

    output reg  [63:0] fp_out,     // 除法结果
    output reg         done,       // 完成信号
    output reg         overflow,   // 上溢标志
    output reg         underflow,  // 下溢标志
    output reg         invalid     // 无效运算标志 (如 0/0, Inf/Inf)
);

    // =============================================================
    // 1. 输入解包 (Decomposition)
    // =============================================================
    wire        sign_a, sign_b;
    wire signed [11:0] exp_a, exp_b; // 扩展符号位以处理指数运算
    wire [52:0] man_a, man_b;        // 包含隐藏位 (1.xxx 或 0.xxx)
    wire        is_nan_a, is_inf_a, is_zero_a, is_denorm_a;
    wire        is_nan_b, is_inf_b, is_zero_b, is_denorm_b;

    // 实例化分解模块: 将 64位 FP 拆解为 符号、阶码、尾数及状态标志
    fp_decomposer u_dec_a (
        .fp_in(fp_a), .sign(sign_a), .exponent(exp_a), .mantissa(man_a),
        .is_nan(is_nan_a), .is_inf(is_inf_a), .is_zero(is_zero_a), .is_denormalized(is_denorm_a)
    );

    fp_decomposer u_dec_b (
        .fp_in(fp_b), .sign(sign_b), .exponent(exp_b), .mantissa(man_b),
        .is_nan(is_nan_b), .is_inf(is_inf_b), .is_zero(is_zero_b), .is_denormalized(is_denorm_b)
    );

    // =============================================================
    // 2. 状态机定义
    // =============================================================
    localparam S_IDLE       = 3'd0; // 空闲
    localparam S_PREPARE    = 3'd1; // 准备：处理特殊情况，初始化寄存器
    localparam S_DIVIDE     = 3'd2; // 除法：执行移位减法
    localparam S_NORMALIZE  = 3'd3; // 规格化：调整商和指数
    localparam S_ROUND      = 3'd4; // 舍入：根据 GRS 位进位
    localparam S_PACK       = 3'd5; // 打包：检查溢出/下溢
    localparam S_DONE       = 3'd6; // 完成

    reg [2:0] state;

    // =============================================================
    // 3. 内部计算寄存器
    // =============================================================
    reg [109:0] remainder_reg; // 余数寄存器 (2倍字长以容纳移位)
    reg [55:0]  quotient_reg;  // 商寄存器 (53位尾数 + G + R + S)
    reg [5:0]   div_cnt;       // 迭代计数器
    
    // 结果暂存信号
    reg        res_sign;
    reg signed [13:0] res_exp; // 扩展位宽防止计算溢出
    reg [52:0] res_man;
    
    // 结果特殊状态标志
    reg res_is_nan;
    reg res_is_inf;
    reg res_is_zero;

    reg [53:0] divisor_core;   // 保存除数的尾数部分

    // =============================================================
    // 4. 特殊情况预判逻辑
    // =============================================================
    wire calc_sign = sign_a ^ sign_b; // 结果符号为两数符号异或
    // 无效运算: 0/0 或 Inf/Inf
    wire is_invalid_op = (is_zero_a && is_zero_b) || (is_inf_a && is_inf_b);
    // 结果为 NaN: 任意输入为 NaN 或 无效运算
    wire check_nan = is_nan_a || is_nan_b || is_invalid_op;
    // 结果为 Inf: 被除数是Inf(且除数非Inf) 或 被除数非特殊且除数是0
    wire check_inf = (is_inf_a && !is_inf_b) || (!is_nan_a && !is_inf_a && !is_zero_a && is_zero_b);
    // 结果为 Zero: 被除数是0(且除数非0/NaN) 或 被除数普通且除数是Inf
    wire check_zero = (is_zero_a && !is_zero_b && !is_nan_b) || (!is_inf_a && !is_nan_a && is_inf_b);

    // =============================================================
    // 5. 舍入逻辑 (fp_rounder)
    // =============================================================
    wire [52:0] rounder_mant_in;
    wire        rounder_g, rounder_r, rounder_s;
    wire [52:0] rounder_mant_out;
    wire        rounder_carry;

    // quotient_reg 布局: [55:3] Mantissa(含隐藏位), [2] Guard, [1] Round, [0] 部分Sticky
    assign rounder_mant_in = quotient_reg[55:3];
    assign rounder_g       = quotient_reg[2];
    assign rounder_r       = quotient_reg[1];
    // Sticky bit: 商的最低位 OR 余数是否仍有残余值
    assign rounder_s       = quotient_reg[0] | (|remainder_reg);

    // 实例化舍入模块
    fp_rounder u_rounder (
        .mant_in   (rounder_mant_in),
        .g         (rounder_g),
        .r         (rounder_r),
        .s         (rounder_s),
        .mant_out  (rounder_mant_out),
        .carry_out (rounder_carry) // 进位标志 (如 1.11... + 1 -> 10.00...)
    );

    // =============================================================
    // 6. 主状态机逻辑
    // =============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            fp_out <= 64'b0;
            done <= 1'b0;
            overflow <= 1'b0;
            underflow <= 1'b0;
            invalid <= 1'b0;
            
            remainder_reg <= 0;
            quotient_reg <= 0;
            div_cnt <= 0;
            divisor_core <= 0;
            
            res_sign <= 0;
            res_exp <= 0;
            res_man <= 0;
            res_is_nan <= 0;
            res_is_inf <= 0;
            res_is_zero <= 0;
            
        end else begin
            done <= 1'b0; 

            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_PREPARE;
                        overflow <= 1'b0;
                        underflow <= 1'b0;
                        invalid <= 1'b0;
                    end
                end

                S_PREPARE: begin
                    res_sign <= calc_sign;
                    // --- 优先级判断特殊情况 ---
                    if (check_nan) begin
                        res_is_nan <= 1'b1;
                        res_is_inf <= 1'b0;
                        res_is_zero <= 1'b0;
                        invalid <= is_invalid_op;
                        state <= S_PACK;
                    end
                    else if (check_inf) begin
                        res_is_nan <= 1'b0;
                        res_is_inf <= 1'b1;
                        res_is_zero <= 1'b0;
                        if (is_zero_b) overflow <= 1'b1; // 除0导致溢出
                        state <= S_PACK;
                    end
                    else if (check_zero) begin
                        res_is_nan <= 1'b0;
                        res_is_inf <= 1'b0;
                        res_is_zero <= 1'b1;
                        state <= S_PACK;
                    end
                    else begin
                        // --- 正常运算初始化 ---
                        res_is_nan <= 1'b0;
                        res_is_inf <= 1'b0;
                        res_is_zero <= 1'b0;
                        // 指数相减 (A - B)
                        res_exp <= $signed(exp_a) - $signed(exp_b);
                        // 初始化余数：被除数放在高位
                        remainder_reg <= {1'b0, man_a, 56'b0}; 
                        divisor_core <= {1'b0, man_b};
                        quotient_reg <= 56'd0;
                        // 需要计算 53位尾数 + 3位保护位(GRS) = 56次迭代
                        div_cnt <= 6'd56; 
                        state <= S_DIVIDE;
                    end
                end

                S_DIVIDE: begin
                    // --- 移位减法算法 ---
                    if (remainder_reg[109:56] >= divisor_core) begin
                         // 够减：余数 = (余数 - 除数) << 1，商位置1
                         remainder_reg <= { (remainder_reg[109:56] - divisor_core), remainder_reg[55:0] } << 1;
                         quotient_reg <= {quotient_reg[54:0], 1'b1};
                    end else begin
                         // 不够减：余数 << 1，商位置0
                         remainder_reg <= remainder_reg << 1;
                         quotient_reg <= {quotient_reg[54:0], 1'b0};
                    end

                    div_cnt <= div_cnt - 1'b1;
                    if (div_cnt == 1) begin
                        state <= S_NORMALIZE;
                    end
                end

                S_NORMALIZE: begin
                    // --- 结果规格化 ---
                    // 检查商的最高位(隐藏位)，如果为0则需左移并将指数减1
                    if (quotient_reg[55]) begin
                        // 已规格化 (1.xxxxx)
                    end else begin
                        quotient_reg <= {quotient_reg[54:0], 1'b0};
                        res_exp <= res_exp - 1'b1;
                    end
                    state <= S_ROUND;
                end

                S_ROUND: begin
                    // --- 舍入处理 ---
                    // u_rounder 模块已根据 GRS 位计算出舍入后的尾数和进位
                    
                    if (rounder_carry) begin
                        // 如果舍入导致进位 (例如 1.11...1 + 1 -> 10.00...0)
                        // 尾数变为0 (隐式1左移了)，指数加1
                        res_man <= 53'b0; 
                        res_exp <= res_exp + 1'sd1;
                    end else begin
                        res_man <= rounder_mant_out;
                    end
                    
                    state <= S_PACK;
                end

                S_PACK: begin
                    // --- 检查溢出与下溢 ---
                    if (!res_is_nan && !res_is_inf && !res_is_zero) begin
                        if (res_exp > 1023) begin
                            // 指数过大 -> 上溢 -> 结果置为 Inf
                            overflow <= 1'b1;
                            res_is_inf <= 1'b1;
                        end else if (res_exp < -1022) begin
                            // 指数过小 -> 下溢 -> 结果置为 Zero (简化处理，未做非规约数渐进下溢)
                            underflow <= 1'b1;
                            res_is_zero <= 1'b1;
                            res_exp <= 0;
                        end
                    end
                    state <= S_DONE;
                end
                
                S_DONE: begin
                    done <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // =============================================================
    // 7. 结果重组 (Recomposition)
    // =============================================================
    wire [10:0] final_exp_field;
    // 根据特殊标志生成最终的 11位 指数域
    assign final_exp_field = (res_is_nan || res_is_inf) ? 11'h7FF : // 全1
                             (res_is_zero)              ? 11'h000 : // 全0
                             (res_exp + 13'd1023);                  // 加上偏置值 1023

    wire [63:0] fp_out_wire;
    // 实例化重组模块：打包 Sign, Exponent, Mantissa
    fp_recomposer u_rec (
        .final_sign(res_sign),
        .final_exponent_field(final_exp_field),
        .final_mantissa_field(res_man[51:0]), // 去掉隐藏位，取低52位小数
        .is_nan_out(res_is_nan),
        .is_inf_out(res_is_inf),
        .is_zero_out(res_is_zero),
        .fp_out(fp_out_wire)
    );
    
    // 输出锁存
    always @(posedge clk) begin
        if (state == S_DONE) begin
            fp_out <= fp_out_wire;
        end
    end

endmodule
`default_nettype wire
