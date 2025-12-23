`timescale 1ns / 1ps

module tb_fp_div;

    // 1. 信号定义
    reg         tb_clk;
    reg         tb_rst_n;      // 注意：设计中使用的是低电平复位 rst_n
    reg         tb_start;      // 开始信号
    reg  [63:0] tb_fp_a;       // 被除数
    reg  [63:0] tb_fp_b;       // 除数
    
    wire [63:0] tb_fp_out;     // 结果输出
    wire        tb_done;       // 完成信号
    wire        tb_overflow;   // 标志位监测
    wire        tb_underflow;
    wire        tb_invalid;

    // 2. 实例化待测模块 (DUT)
    fp_div uut (
        .clk        (tb_clk),
        .rst_n      (tb_rst_n),
        .start      (tb_start),
        .fp_a       (tb_fp_a),
        .fp_b       (tb_fp_b),
        .fp_out     (tb_fp_out),
        .done       (tb_done),
        .overflow   (tb_overflow),
        .underflow  (tb_underflow),
        .invalid    (tb_invalid)
    );

    // 3. 时钟生成 (10ns 周期 -> 100MHz)
    always #5 tb_clk = ~tb_clk;

    // 4. 定义测试任务
    task run_test;
        input [63:0] a;
        input [63:0] b;
        input [63:0] expected;
        input [511:0] test_name; // 增加字符串长度以防截断
        
        reg [31:0] timeout_counter;
        begin
            @(posedge tb_clk);
            tb_fp_a = a;
            tb_fp_b = b;
            tb_start = 1; // 发送 Start 脉冲
            @(posedge tb_clk);
            tb_start = 0;
            
            // 等待 done 信号
            timeout_counter = 0;
            while (!tb_done && timeout_counter < 200) begin
                @(posedge tb_clk);
                timeout_counter = timeout_counter + 1;
            end

            // 结果检查
            if (timeout_counter >= 200) begin
                $display("ERROR: %0s. Test timed out!", test_name);
            end else begin
                // 使用 === 进行严格比对 (包括 x/z，尽管这里预期是确定的值)
                // 注意：对于 NaN，FP标准中 NaN != NaN，但在硬件仿真中我们比对位模式
                if (tb_fp_out === expected) begin
                    $display("PASS: %-45s. Got=%h (Flags: Ov=%b Un=%b Inv=%b)", 
                             test_name, tb_fp_out, tb_overflow, tb_underflow, tb_invalid);
                end else begin
                    $display("FAIL: %-45s. Expected=%h, Got=%h", test_name, expected, tb_fp_out);
                end
            end
            
            // 插入一点间隙
            repeat(2) @(posedge tb_clk);
        end
    endtask

    // 5. 测试主流程
    initial begin
        // 初始化
        tb_clk = 0;
        tb_rst_n = 0; // 复位有效
        tb_start = 0;
        tb_fp_a = 0;
        tb_fp_b = 0;

        // 生成波形文件 (可选)
        $dumpfile("./vcd/tb_fp_div.vcd");
        $dumpvars(0, tb_fp_div);

        // 释放复位
        #20;
        @(posedge tb_clk);
        tb_rst_n = 1;
        @(posedge tb_clk);
        
        $display("================== Start Test fp_div_64 ==================");

        // --- 基础运算 ---
        // 6.0 / 2.0 = 3.0
        run_test(64'h4018000000000000, 64'h4000000000000000, 64'h4008000000000000, 
                 "Test 1: 6.0 / 2.0 (Basic)"); 
                 
        // -6.0 / 2.0 = -3.0 (符号位测试)
        run_test(64'hC018000000000000, 64'h4000000000000000, 64'hC008000000000000, 
                 "Test 2: -6.0 / 2.0 (Sign Mix)");
                 
        // 1.0 / 1.0 = 1.0 (单位测试)
        run_test(64'h3FF0000000000000, 64'h3FF0000000000000, 64'h3FF0000000000000, 
                 "Test 3: 1.0 / 1.0 (Identity)"); 

        // --- 精度与舍入 ---
        // 1.0 / 3.0 = 0.3333... (测试 Guard/Round/Sticky 逻辑)
        // 预期结果：3FD5555555555555
        run_test(64'h3FF0000000000000, 64'h4008000000000000, 64'h3FD5555555555555, 
                 "Test 4: 1.0 / 3.0 (Rounding check)");

        // 1.0 / 10.0 = 0.1 (常见循环小数)
        // 1.0: 3FF0000000000000, 10.0: 4024000000000000
        // 0.1: 3FB999999999999A (Round to Nearest Even, clear distinct pattern)
        run_test(64'h3FF0000000000000, 64'h4024000000000000, 64'h3FB999999999999A, 
                 "Test 5: 1.0 / 10.0 (Precision)");

        // --- 特殊值处理 (Exceptions) ---
        
        // 5.0 / 0.0 = +Inf (除零异常)
        // Inf Hex: 7FF0000000000000
        run_test(64'h4014000000000000, 64'h0000000000000000, 64'h7FF0000000000000, 
                 "Test 6: 5.0 / 0.0 (Div by Zero -> Inf)");  
        
        // 0.0 / 5.0 = 0.0 (被除数为0)
        run_test(64'h0000000000000000, 64'h4014000000000000, 64'h0000000000000000, 
                 "Test 7: 0.0 / 5.0 (Zero Numerator)"); 

        // 0.0 / 0.0 = NaN (非法操作)
        // 本设计中 NaN 定义为: 7FF8000000000001
        run_test(64'h0000000000000000, 64'h0000000000000000, 64'h7FF8000000000001, 
                 "Test 8: 0.0 / 0.0 (Invalid -> NaN)"); 
        
        // 5.0 / Inf = 0.0
        run_test(64'h4014000000000000, 64'h7FF0000000000000, 64'h0000000000000000, 
                 "Test 9: 5.0 / Inf (Div by Inf -> 0)"); 
        
        // Inf / Inf = NaN
        run_test(64'h7FF0000000000000, 64'h7FF0000000000000, 64'h7FF8000000000001, 
                 "Test 10: Inf / Inf (Invalid -> NaN)");  
        
        // NaN / 5.0 = NaN (NaN 传播)
        run_test(64'h7FF8000000000001, 64'h4014000000000000, 64'h7FF8000000000001, 
                 "Test 11: NaN / 5.0 (NaN Propagation)"); 

        // --- 边界情况：下溢 (Flush to Zero) ---
        // 最小规格化数 / 2^100 
        // A = 2^-1022 (Min Normal) = 0010000000000000
        // B = 2^100  = 4630000000000000
        // Res 应该下溢为 0
        run_test(64'h0010000000000000, 64'h4630000000000000, 64'h0000000000000000, 
                 "Test 12: Min_Norm / Large (Underflow -> 0)");

        $display("================== Stop Test fp_div_64 ==================");
        #20;
        $finish;
    end

endmodule
