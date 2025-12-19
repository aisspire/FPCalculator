// src/common/lzc_64.v
// 功能：计算64位数据的前导零数量
// 方法：层次化设计，性能和面积更优，是工程中的常用方法。

`default_nettype none

module lzc_64_hierarchical (
    input  wire [63:0] data_in,
    output reg  [6:0]  count
);
    always @(*) begin
        if (data_in[63:32] != 0) begin
            // 在高32位中查找
            if (data_in[63:48] != 0) begin // 在高16位中查找
                if (data_in[63:56] != 0) begin // 在高8位中查找
                    if (data_in[63:60] != 0) begin // 在高4位中查找
                        if (data_in[63:62] != 0) begin // 在高2位中查找
                            if (data_in[63] == 1'b1) count = 0; else count = 1; // 63 or 62
                        end else begin
                            if (data_in[61] == 1'b1) count = 2; else count = 3; // 61 or 60
                        end
                    end else begin // 在低4位中查找
                        if (data_in[59:58] != 0) begin
                            if (data_in[59] == 1'b1) count = 4; else count = 5; // 59 or 58
                        end else begin
                            if (data_in[57] == 1'b1) count = 6; else count = 7; // 57 or 56
                        end
                    end
                end else begin // 在低8位中查找 (bits 55:48)
                    // ... 此处逻辑与上面类似，可以继续展开 ...
                    // 为了简洁，我们换一种方式来表达这个层级
                    // 只要找到第一个不为0的块，就可以进行最终的casez判断
                    // 下面是另一种等效且更紧凑的层次化写法
                    count = 8 + lzc_8(data_in[55:48]);
                end
            end else begin // 在低16位中查找 (bits 47:32)
                count = 16 + lzc_16(data_in[47:32]);
            end
        end else begin
            // 在低32位中查找
            count = 32 + lzc_32(data_in[31:0]);
        end
    end

    // 为使上述代码工作，你需要定义 lzc_32, lzc_16, lzc_8 等函数或模块
    // 这里提供一个更扁平化的层次结构，避免递归调用，更适合综合

    always @(*) begin
        if (data_in == 0) begin
            count = 64;
        end else if (data_in[63:32] != 0) begin
            count = lzc_32(data_in[63:32]);
        end else begin
            count = 32 + lzc_32(data_in[31:0]);
        end
    end

    // 32位前导零计数器函数
    function [5:0] lzc_32 (input [31:0] d);
        if (d[31:16] != 0) lzc_32 = lzc_16(d[31:16]);
        else lzc_32 = 16 + lzc_16(d[15:0]);
    endfunction

    // 16位前导零计数器函数
    function [4:0] lzc_16 (input [15:0] d);
        if (d[15:8] != 0) lzc_16 = lzc_8(d[15:8]);
        else lzc_16 = 8 + lzc_8(d[7:0]);
    endfunction

    // 8位前导零计数器函数
    function [3:0] lzc_8 (input [7:0] d);
        if (d[7:4] != 0) begin
            casez(d[7:4])
                4'b1???: lzc_8 = 0;
                4'b01??: lzc_8 = 1;
                4'b001?: lzc_8 = 2;
                4'b0001: lzc_8 = 3;
            endcase
        end else begin
            casez(d[3:0])
                4'b1???: lzc_8 = 4;
                4'b01??: lzc_8 = 5;
                4'b001?: lzc_8 = 6;
                4'b0001: lzc_8 = 7;
                default: lzc_8 = 8; // Should not happen if d != 0
            endcase
        end
    endfunction

endmodule
`default_nettype wire
