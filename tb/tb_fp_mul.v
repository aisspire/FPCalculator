`timescale 1ns / 1ps

module tb_fp_mul;

    // 1. 信号定义
    // 由于 fp_mul 接口定义中没有时钟和复位，这里作为组合逻辑测试
    reg  [63:0] tb_a;       // 乘数 A
    reg  [63:0] tb_b;       // 乘数 B
    
    wire [63:0] tb_res;     // 结果输出

    // 2. 实例化待测模块 (DUT)
    fp_mul uut (
        .a          (tb_a),
        .b          (tb_b),
        .res        (tb_res)
    );

    // 3. 定义测试任务
    task run_test;
        input [63:0] a;
        input [63:0] b;
        input [63:0] expected;
        input [511:0] test_name;
        
        begin
            // 赋值输入
            tb_a = a;
            tb_b = b;
            
            // 等待组合逻辑稳定 (假设延迟小于 10ns)
            // 如果实际设计是流水的但未暴露时钟，这里需要根据实际情况调整
            #10;

            // 结果检查
            // 使用 === 进行严格比对
            if (tb_res === expected) begin
                $display("PASS: %-45s. Got=%h", test_name, tb_res);
            end else begin
                $display("FAIL: %-45s. Expected=%h, Got=%h", test_name, expected, tb_res);
            end
            
            // 插入一点间隙方便波形观察
            #10;
        end
    endtask

    // 4. 测试主流程
    initial begin
        // 初始化
        tb_a = 0;
        tb_b = 0;

        // 生成波形文件 (可选)
        $dumpfile("tb_fp_mul.vcd");
        $dumpvars(0, tb_fp_mul);
        
        $display("================== 开始测试 fp_mul_64 ==================");
        #10;

        // --- 基础运算 ---
        // 2.0 * 3.0 = 6.0
        // 2.0: 4000000000000000, 3.0: 4008000000000000, 6.0: 4018000000000000
        run_test(64'h4000000000000000, 64'h4008000000000000, 64'h4018000000000000, 
                 "Test 1: 2.0 * 3.0 = 6.0 (Basic)"); 
                 
        // -2.0 * 3.0 = -6.0 (符号位测试)
        // -2.0: C000000000000000, -6.0: C018000000000000
        run_test(64'hC000000000000000, 64'h4008000000000000, 64'hC018000000000000, 
                 "Test 2: -2.0 * 3.0 = -6.0 (Sign Check)");
                 
        // -2.0 * -3.0 = 6.0
        run_test(64'hC000000000000000, 64'hC008000000000000, 64'h4018000000000000, 
                 "Test 3: -2.0 * -3.0 = 6.0 (Neg * Neg)");

        // --- 恒等与零 ---
        // X * 1.0 = X
        run_test(64'h4059000000000000, 64'h3FF0000000000000, 64'h4059000000000000, 
                 "Test 4: 100.0 * 1.0 = 100.0 (Identity)"); 

        // X * 0.0 = 0.0
        run_test(64'h4014000000000000, 64'h0000000000000000, 64'h0000000000000000, 
                 "Test 5: 5.0 * 0.0 = 0.0 (Zero Property)");
                 
          // --- 舍入测试 (平衡舍入 Round to Nearest Even) ---
        
        // 用例 A: 结果为 Tie 且 LSB 为奇数 (Odd) -> 应该进位 (Round Up)
        // 输入 A: 1.0 + 2^-52           (1.00...01)      Hex: 3FF0000000000001
        // 输入 B: 1.5                   (1.1)            Hex: 3FF8000000000000
        // 计算过程:
        // (1 + 2^-52) * 1.5 = 1.5 + 1.5*2^-52 
        //                   = 1.5 + 2^-52 + 2^-53
        //                   = 1.10...01 1 (二进制)
        // LSB (2^-52位) 是 1 (奇数)。Guard (2^-53位) 是 1。
        // 期望结果: 进位后变成 1.5 + 2*2^-52 = 1.5 + 2^-51
        // Hex: 3FF8000000000002
        run_test(64'h3FF0000000000001, 64'h3FF8000000000000, 64'h3FF8000000000002, 
                 "Test 6A: (1.0?)*1.5 = (1.5?) (Odd LSB -> Round Up)");

        // 用例 B: 结果为 Tie 且 LSB 为偶数 (Even) -> 应该截断 (Round Down)
        // 输入 A: 1.0 + 2^-51 + 2^-52   (1.00...011)     Hex: 3FF0000000000003
        // 输入 B: 1.5                   (1.1)            Hex: 3FF8000000000000
        // 计算过程:
        // (1 + 2^-51 + 2^-52) * 1.5
        // = 1.5 + 1.5*(2^-51 + 2^-52)
        // = 1.5 + 1.5*2^-51 + 1.5*2^-52
        // ... (经过二进制加法) ...
        // = 1.5 + 2^-50 + 2^-53
        // = 1.10...0100...00 1 (二进制)
        // LSB (2^-52位) 是 0 (偶数)。Guard (2^-53位) 是 1。
        // 注意：这里 2^-50 使得 bit[2] 为 1，而 LSB bit[0] 为 0。
        // 期望结果: 保持截断，舍去 2^-53
        // 结果 = 1.5 + 2^-50
        // Hex: 3FF8000000000004
        run_test(64'h3FF0000000000003, 64'h3FF8000000000000, 64'h3FF8000000000004, 
                 "Test 6B: (1.0?)*1.5 = (1.5?) (Even LSB -> Round Down)");


        // --- 特殊值处理 (Exceptions) ---
        
        // 5.0 * Inf = Inf
        // Inf: 7FF0000000000000
        run_test(64'h4014000000000000, 64'h7FF0000000000000, 64'h7FF0000000000000, 
                 "Test 7: 5.0 * Inf = Inf");  
        
        // -5.0 * Inf = -Inf
        // -Inf: FFF0000000000000
        run_test(64'hC014000000000000, 64'h7FF0000000000000, 64'hFFF0000000000000, 
                 "Test 8: -5.0 * Inf = -Inf"); 

        // 0.0 * Inf = NaN (非法操作)
        // 0.0: 0000... , Inf: 7FF0... 
        // 预期 NaN: 7FF8000000000001 (参考除法TB中的定义)
        run_test(64'h0000000000000000, 64'h7FF0000000000000, 64'h7FF8000000000001, 
                 "Test 9: 0.0 * Inf = NaN"); 
        
        // Inf * Inf = Inf
        run_test(64'h7FF0000000000000, 64'h7FF0000000000000, 64'h7FF0000000000000, 
                 "Test 10: Inf * Inf = Inf"); 
        
        // NaN * 5.0 = NaN (NaN 传播)
        // NaN: 7FF8000000000001
        run_test(64'h7FF8000000000001, 64'h4014000000000000, 64'h7FF8000000000001, 
                 "Test 11: NaN * 5.0 = NaN"); 

        // --- 边界情况：溢出 (Overflow) ---
        // Max_Double * 2.0 = Inf
        // Max_Double: 7FEFFFFFFFFFFFFF
        run_test(64'h7FEFFFFFFFFFFFFF, 64'h4000000000000000, 64'h7FF0000000000000, 
                 "Test 12: Max_Double * 2.0 -> Overflow to Inf");

        // --- 边界情况：下溢 (Underflow / Flush to Zero) ---
        // Min_Normal * Small_Number
        // Min_Normal (2^-1022): 0010000000000000
        // Multiply by 2^-100 (Small): 39B0000000000000 (approx, exponent is what matters)
        // Let's use specific small powers of 2.
        // 2^-1022 * 2^-53 = 2^-1075 (Should underflow to 0 with standard rounding)
        // 2^-53: 3CA0000000000000
        run_test(64'h0010000000000000, 64'h3CA0000000000000, 64'h0000000000000000, 
                 "Test 13: Min_Norm * 2^-53 -> Underflow to 0");

        $display("================== 结束测试 fp_mul_64 ==================");
        #20;
        $finish;
    end

endmodule
