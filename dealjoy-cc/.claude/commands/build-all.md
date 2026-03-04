请按以下顺序为 DealJoy 生成全栈代码。每个模块用独立的 Task 子代理执行（隔离上下文，避免溢出）。

模块执行顺序：
$ARGUMENTS

如果没有指定参数，默认顺序为：
1. 5.下单与支付
2. 6.团购券系统
3. 7.退款系统
4. 4.Deal详情页
5. 2.首页与推荐
6. 3.搜索系统
7. 8.订单管理
8. 9.评价系统
9. 10.个人中心

---

对每个模块，启动一个 Task 子代理，传入以下指令：

"""
你是 DealJoy 全栈开发工程师。请为模块 "{模块名}" 生成完整代码。

步骤：
1. 运行 python3 scripts/read_excel.py "{模块名}" 获取需求
2. 读取 docs/flutter/patterns.md、docs/supabase/patterns.md、docs/business/rules.md
3. 读取 output/ 下已完成模块的代码，确保数据模型、API风格、错误码格式一致
4. 生成文件到 output/{模块名}/ 目录：
   - 03_backend/migrations/*.sql（数据库）
   - 03_backend/functions/**/*.ts（Edge Functions）
   - 03_backend/policies/*.sql（RLS 策略）
   - 04_frontend/lib/features/{feature}/**/*.dart（Flutter）
5. 运行 flutter analyze（如果 Flutter 环境可用），修复所有 error
6. 完成后输出摘要：生成了哪些文件、几张表、几个 API、几个页面

代码规范：
- 前端除注释外全部英文
- 注释用中文
- 遵循 docs/ 下的代码模式
- 错误码参照 docs/business/rules.md
"""

每个子代理完成后，打印进度：
✅ [1/7] 5.下单与支付 — 完成（X 个文件）
✅ [2/7] 6.团购券系统 — 完成（X 个文件）
...

全部完成后打印：
🎉 所有模块生成完毕！共生成 X 个文件。
