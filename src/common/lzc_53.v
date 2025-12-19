// src/common/lzc_53.v
// 功能：计算53位数据的前导零数量

`default_nettype none

module lzc_53 (
    input  wire [52:0] data_in,   // 输入数据
    output reg  [5:0]  count      // 输出的前导零数量
);

    // 这是一个组合逻辑模块，使用 always @(*)
    always @(*) begin
        // 这是一个优先级的判断结构
        // 从最高位(MSB)开始检查
        if      (data_in[52]) count = 0;
        else if (data_in[51]) count = 1;
        else if (data_in[50]) count = 2;
        else if (data_in[49]) count = 3;
        else if (data_in[48]) count = 4;
        else if (data_in[47]) count = 5;
        else if (data_in[46]) count = 6;
        else if (data_in[45]) count = 7;
        else if (data_in[44]) count = 8;
        else if (data_in[43]) count = 9;
        else if (data_in[42]) count = 10;
        else if (data_in[41]) count = 11;
        else if (data_in[40]) count = 12;
        else if (data_in[39]) count = 13;
        else if (data_in[38]) count = 14;
        else if (data_in[37]) count = 15;
        else if (data_in[36]) count = 16;
        else if (data_in[35]) count = 17;
        else if (data_in[34]) count = 18;
        else if (data_in[33]) count = 19;
        else if (data_in[32]) count = 20;
        else if (data_in[31]) count = 21;
        else if (data_in[30]) count = 22;
        else if (data_in[29]) count = 23;
        else if (data_in[28]) count = 24;
        else if (data_in[27]) count = 25;
        else if (data_in[26]) count = 26;
        else if (data_in[25]) count = 27;
        else if (data_in[24]) count = 28;
        else if (data_in[23]) count = 29;
        else if (data_in[22]) count = 30;
        else if (data_in[21]) count = 31;
        else if (data_in[20]) count = 32;
        else if (data_in[19]) count = 33;
        else if (data_in[18]) count = 34;
        else if (data_in[17]) count = 35;
        else if (data_in[16]) count = 36;
        else if (data_in[15]) count = 37;
        else if (data_in[14]) count = 38;
        else if (data_in[13]) count = 39;
        else if (data_in[12]) count = 40;
        else if (data_in[11]) count = 41;
        else if (data_in[10]) count = 42;
        else if (data_in[9])  count = 43;
        else if (data_in[8])  count = 44;
        else if (data_in[7])  count = 45;
        else if (data_in[6])  count = 46;
        else if (data_in[5])  count = 47;
        else if (data_in[4])  count = 48;
        else if (data_in[3])  count = 49;
        else if (data_in[2])  count = 50;
        else if (data_in[1])  count = 51;
        else if (data_in[0])  count = 52;
        else                  count = 53; // 如果所有位都是0
    end

endmodule

`default_nettype wire
