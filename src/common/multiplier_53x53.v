// src/common/multiplier_53x53.v
// 功能：计算两个53位无符号数的乘积

`default_nettype none

module multiplier_53x53 (
    input  wire [52:0] a,       // 操作数A
    input  wire [52:0] b,       // 操作数B
    
    output wire [105:0] product // 106位的乘积 (53+53)
);

    // 使用乘法运算符，综合工具会自动优化
    assign product = a * b;

endmodule

`default_nettype wire
