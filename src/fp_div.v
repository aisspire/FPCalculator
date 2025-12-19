// src/fp_div.v
// 功能：实现IEEE 754双精度浮点数的除法

`default_nettype none

module fp_div (
    input  wire        clk,
    input  wire        reset,
    input  wire [63:0] fp_a_in,
    input  wire [63:0] fp_b_in,
    output wire [63:0] fp_res_out
);
    // --- 子模块实例化 ---
    // (此处省略了 decomposer, rounder, recomposer 的实例化代码，假设它们存在)

    // --- 除法器实例化 ---
    wire [55:0] raw_quotient;
    wire [52:0] raw_remainder;
    wire        divider_ready;
    reg         divider_start;

    // 假设 decomposer 已分解出 mant_a 和 mant_b
    restoring_divider divider (
        .clk(clk), .reset(reset), .start(divider_start),
        .dividend_in(mant_a), .divisor_in(mant_b),
        .quotient_out(raw_quotient), .remainder_out(raw_remainder), .ready(divider_ready)
    );

    // --- 状态机与控制逻辑 ---
    // (此处为伪代码，展示核心逻辑流程)
    // 状态定义: IDLE, DECOMPOSE, DIV_WAIT, NORM_ROUND, DONE

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // 初始化状态
        end else begin
            case (state)
                IDLE: // 等待新操作
                
                DECOMPOSE:
                    // 分解 A 和 B
                    // 检查所有特殊情况 (NaN, Inf, Zero)
                    // if (special_case) -> 直接计算结果, state <= DONE
                    // else ->
                    //   final_sign <= sign_a ^ sign_b
                    //   final_exp <= exp_a - exp_b
                    //   a_lt_b <= mant_a < mant_b // 比较尾数大小
                    //   divider_start <= 1
                    //   state <= DIV_WAIT
                
                DIV_WAIT:
                    // divider_start <= 0
                    // if (divider_ready) -> state <= NORM_ROUND
                
                NORM_ROUND:
                    // --- 规格化 ---
                    // if (a_lt_b) // 商是 0.1xxx..., 需要左移
                    //   norm_exp = final_exp - 1
                    //   norm_mant = raw_quotient[54:2]
                    //   g = raw_quotient[1]
                    //   r = raw_quotient[0]
                    // else // 商是 1.xxxx...
                    //   norm_exp = final_exp
                    //   norm_mant = raw_quotient[55:3]
                    //   g = raw_quotient[2]
                    //   r = raw_quotient[1]
                    //
                    // s = (raw_remainder != 0) || raw_quotient[0] // 粘滞位
                    
                    // --- 舍入 ---
                    // 调用 fp_rounder
                    // 处理舍入进位
                    
                    // --- 准备重组 ---
                    // state <= DONE
                    
                DONE:
                    // 调用 fp_recomposer
                    // 输出最终结果 fp_res_out
                    // state <= IDLE
            endcase
        end
    end

endmodule
`default_nettype wire
