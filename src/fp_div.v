`default_nettype none
module fp_div (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [63:0] fp_a,
    input  wire [63:0] fp_b,

    output reg  [63:0] fp_out,
    output reg         done,
    output reg         overflow,
    output reg         underflow,
    output reg         invalid
);

    // ... (实例化分解模块部分) ...
    wire        sign_a, sign_b;
    wire signed [11:0] exp_a, exp_b;
    wire [52:0] man_a, man_b;
    wire        is_nan_a, is_inf_a, is_zero_a, is_denorm_a;
    wire        is_nan_b, is_inf_b, is_zero_b, is_denorm_b;

    // 假设 fp_decomposer 存在于项目中
    fp_decomposer u_dec_a (
        .fp_in(fp_a), .sign(sign_a), .exponent(exp_a), .mantissa(man_a),
        .is_nan(is_nan_a), .is_inf(is_inf_a), .is_zero(is_zero_a), .is_denormalized(is_denorm_a)
    );

    fp_decomposer u_dec_b (
        .fp_in(fp_b), .sign(sign_b), .exponent(exp_b), .mantissa(man_b),
        .is_nan(is_nan_b), .is_inf(is_inf_b), .is_zero(is_zero_b), .is_denormalized(is_denorm_b)
    );

    localparam S_IDLE       = 3'd0;
    localparam S_PREPARE    = 3'd1;
    localparam S_DIVIDE     = 3'd2;
    localparam S_NORMALIZE  = 3'd3;
    localparam S_ROUND      = 3'd4;
    localparam S_PACK       = 3'd5;
    localparam S_DONE       = 3'd6;

    reg [2:0] state;

    reg [109:0] remainder_reg;
    reg [55:0]  quotient_reg;
    reg [5:0]   div_cnt;
    
    reg        res_sign;
    reg signed [13:0] res_exp;
    reg [52:0] res_man;
    
    reg res_is_nan;
    reg res_is_inf;
    reg res_is_zero;

    reg [53:0] divisor_core; 

    wire calc_sign = sign_a ^ sign_b;
    wire is_invalid_op = (is_zero_a && is_zero_b) || (is_inf_a && is_inf_b);
    wire check_nan = is_nan_a || is_nan_b || is_invalid_op;
    wire check_inf = (is_inf_a && !is_inf_b) || (!is_nan_a && !is_inf_a && !is_zero_a && is_zero_b);
    wire check_zero = (is_zero_a && !is_zero_b && !is_nan_b) || (!is_inf_a && !is_nan_a && is_inf_b);

    // =============================================================
    // 实例化 fp_rounder 模块 logic
    // =============================================================
    wire [52:0] rounder_mant_in;
    wire        rounder_g;
    wire        rounder_r;
    wire        rounder_s;
    wire [52:0] rounder_mant_out;
    wire        rounder_carry;

    // quotient_reg 在 S_NORMALIZE 之后是 [55:0]
    // [55] 是隐藏位 (1)
    // [54:3] 是小数部分 (52位) -> 合计 [55:3] 为 53 位 Mantissa
    // [2] 是 Guard bit
    // [1] 是 Round bit
    // [0] 是 Sticky bit 的一部分 (还需要结合 remainder)
    
    assign rounder_mant_in = quotient_reg[55:3];
    assign rounder_g       = quotient_reg[2];
    assign rounder_r       = quotient_reg[1];
    // Sticky bit: 当前商的最低位 OR 余数是否非零
    assign rounder_s       = quotient_reg[0] | (|remainder_reg);

    fp_rounder u_rounder (
        .mant_in   (rounder_mant_in),
        .g         (rounder_g),
        .r         (rounder_r),
        .s         (rounder_s),
        .mant_out  (rounder_mant_out),
        .carry_out (rounder_carry)
    );
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
                        if (is_zero_b) overflow <= 1'b1;
                        state <= S_PACK;
                    end
                    else if (check_zero) begin
                        res_is_nan <= 1'b0;
                        res_is_inf <= 1'b0;
                        res_is_zero <= 1'b1;
                        state <= S_PACK;
                    end
                    else begin
                        res_is_nan <= 1'b0;
                        res_is_inf <= 1'b0;
                        res_is_zero <= 1'b0;
                        res_exp <= $signed(exp_a) - $signed(exp_b);
                        // 预留足够位数用于除法
                        remainder_reg <= {1'b0, man_a, 56'b0}; 
                        divisor_core <= {1'b0, man_b};
                        quotient_reg <= 56'd0;
                        div_cnt <= 6'd56; 
                        state <= S_DIVIDE;
                    end
                end

                S_DIVIDE: begin
                    if (remainder_reg[109:56] >= divisor_core) begin
                         // 够减
                         remainder_reg <= { (remainder_reg[109:56] - divisor_core), remainder_reg[55:0] } << 1;
                         quotient_reg <= {quotient_reg[54:0], 1'b1};
                    end else begin
                         remainder_reg <= remainder_reg << 1;
                         quotient_reg <= {quotient_reg[54:0], 1'b0};
                    end

                    div_cnt <= div_cnt - 1'b1;
                    if (div_cnt == 1) begin
                        state <= S_NORMALIZE;
                    end
                end

                S_NORMALIZE: begin
                    // 标准化商，确保第55位是1
                    if (quotient_reg[55]) begin
                        // 已规格化
                    end else begin
                        quotient_reg <= {quotient_reg[54:0], 1'b0};
                        res_exp <= res_exp - 1'b1;
                    end
                    state <= S_ROUND;
                end

                S_ROUND: begin
                    // 使用 fp_rounder 的输出
                    // 如果产生 carry_out，说明尾数 1.11...1 + 1 变成了 10.00...0
                    // 此时 rounder_mant_out 通常变为 0，我们需要增加指数
                    
                    if (rounder_carry) begin
                        res_man <= 53'b0; // 实际值是 10.0...，recomposer取低52位为0
                        res_exp <= res_exp + 1'sd1;
                    end else begin
                        res_man <= rounder_mant_out;
                    end
                    
                    state <= S_PACK;
                end

                S_PACK: begin
                    if (!res_is_nan && !res_is_inf && !res_is_zero) begin
                        if (res_exp > 1023) begin
                            overflow <= 1'b1;
                            res_is_inf <= 1'b1;
                        end else if (res_exp < -1022) begin
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

    wire [10:0] final_exp_field;
    assign final_exp_field = (res_is_nan || res_is_inf) ? 11'h7FF :
                             (res_is_zero)              ? 11'h000 :
                             (res_exp + 13'd1023);

    wire [63:0] fp_out_wire;
    // 假设 fp_recomposer 存在
    fp_recomposer u_rec (
        .final_sign(res_sign),
        .final_exponent_field(final_exp_field),
        .final_mantissa_field(res_man[51:0]), // 取低52位小数部分
        .is_nan_out(res_is_nan),
        .is_inf_out(res_is_inf),
        .is_zero_out(res_is_zero),
        .fp_out(fp_out_wire)
    );
    
    always @(posedge clk) begin
        if (state == S_DONE) begin
            fp_out <= fp_out_wire;
        end
    end

endmodule
`default_nettype wire
