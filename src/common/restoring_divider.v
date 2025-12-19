// src/common/restoring_divider.v
// 功能：56周期恢复余数除法器 (53位 / 53位 -> 56位商)

`default_nettype none

module restoring_divider (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,          // 开始信号

    input  wire [52:0] dividend_in,  // 被除数 A
    input  wire [52:0] divisor_in,   // 除数 B

    output reg  [55:0] quotient_out,   // 56位商
    output reg  [52:0] remainder_out,  // 53位余数
    output reg         ready           // 完成信号
);

    // 状态机状态
    localparam S_IDLE = 2'b00;
    localparam S_CALC = 2'b01;
    localparam S_DONE = 2'b10;

    reg [1:0] state, next_state;

    // 内部寄存器
    reg [52:0] divisor_reg;      // 除数寄存器
    reg [108:0] rem_q_reg;       // [108:53]为余数, [52:0]为未来的商位
    reg [5:0]  cycle_counter;    // 循环计数器 (0-56)

    // 组合逻辑部分
    wire [53:0] current_rem = rem_q_reg[108:55];
    wire [53:0] sub_result = current_rem - divisor_reg;
    wire        q_bit = ~sub_result[53]; // 如果结果非负, q_bit = 1

    always @(*) begin
        next_state = state;
        ready = 1'b0;

        case(state)
            S_IDLE: if (start) next_state = S_CALC;
            S_CALC: if (cycle_counter == 0) next_state = S_DONE;
            S_DONE: begin
                ready = 1'b1;
                next_state = S_IDLE;
            end
        endcase
    end

    // 时序逻辑部分
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            cycle_counter <= 0;
            quotient_out <= 0;
            remainder_out <= 0;
        end else begin
            state <= next_state;

            case(state)
                S_IDLE: begin
                    if (start) begin
                        rem_q_reg <= {56'd0, dividend_in};
                        divisor_reg <= divisor_in;
                        cycle_counter <= 56;
                    end
                end
                
                S_CALC: begin
                    rem_q_reg[108:53] <= q_bit ? sub_result[52:0] : current_rem[52:0];
                    rem_q_reg[52:0] <= rem_q_reg[51:0]; // 为下一位腾出空间
                    rem_q_reg[53] <= q_bit;
                    cycle_counter <= cycle_counter - 1;
                end

                S_DONE: begin
                    quotient_out <= rem_q_reg[55:0];
                    remainder_out <= rem_q_reg[108:56];
                end
            endcase
        end
    end

endmodule

`default_nettype wire
