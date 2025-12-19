// src/common/add_sub_53.v
// 功能：执行53位尾数的加法或减法

`default_nettype none

module add_sub_53 (
    input  wire [52:0] a,        // 操作数A
    input  wire [52:0] b,        // 操作数B
    input  wire        is_sub,   // 运算选择, 1'b1=减法, 1'b0=加法

    output wire [53:0] result    // 54位结果 (含进位)
);

    // 根据 is_sub 信号，对操作数B进行处理
    // 如果是减法，B取反；如果是加法，B保持原样。
    wire [52:0] b_operand = is_sub ? ~b : b;
    
    // is_sub 信号也作为加法器的最低位进位输入
    // 加法: cin = 0; 减法: cin = 1
    wire        cin = is_sub;

    // 执行加法运算
    // result = A + B_processed + cin
    assign result = a + b_operand + cin;

endmodule

`default_nettype wire
