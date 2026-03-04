为 DealJoy 的 **$ARGUMENTS** 模块执行完整开发。**直接修改 `deal_joy/` 目录下的代码**。

## 第 1 步: 需求分析
1. 运行 `python3 scripts/read_excel.py "$ARGUMENTS"` 获取需求
2. 扫描 `deal_joy/lib/features/` 中与该模块相关的 **所有现有代码**
3. 对比需求和现有代码，列出：
   - 已实现的功能
   - 需要修改/完善的功能
   - 需要新建的功能
4. 保存分析到 `.pipeline/$ARGUMENTS/01_analysis.json`

## 第 2 步: 制定计划
1. 根据分析结果，制定具体修改计划
2. 每个任务必须明确：修改哪个文件、改什么、为什么
3. 优先级：修复 bug > 补全现有功能 > 新增功能
4. 保存计划到 `.pipeline/$ARGUMENTS/02_plan.md`

## 第 3 步: 后端补全
1. 检查 `deal_joy/supabase/schema.sql` 和 `deal_joy/supabase/migrations/`
2. 如果需要新表或修改表结构，创建新的 migration 文件
3. 如果需要新的 Edge Function，创建到 `deal_joy/supabase/functions/`
4. 确保所有表都有 RLS 策略

## 第 4 步: 前端开发
**直接修改 `deal_joy/lib/` 中的文件**：
1. 修复现有代码的 bug 和未完成部分
2. 补全缺失的 repository、model、provider、screen
3. 确保路由 `deal_joy/lib/core/router/app_router.dart` 正确配置
4. 遵循现有目录结构：data/repositories/, data/models/, domain/providers/, presentation/screens/
5. UI 文案全英文，注释中文

## 第 5 步: 代码审查 + 修复
1. 检查所有修改过的文件
2. 安全审查：RLS 策略、输入校验、密钥处理
3. 一致性检查：前后端 API 契约、Model 字段对齐
4. **发现问题直接修复，不只是报告**

## 第 6 步: 测试验证
1. 修复 `deal_joy/test/widget_test.dart`（MyApp → DealJoyApp）
2. 为修改的功能编写测试到 `deal_joy/test/`
3. 运行 `cd deal_joy && flutter test`
4. 测试失败则修复后重跑，直到通过

## 完成后
汇总报告：修改了哪些文件、新增了哪些文件、测试结果。

## 第 7 步: 自动进入 Ralph Loop 循环打磨
Pipeline 完成后，自动执行以下命令启动循环：

```!
.claude/scripts/setup-ralph-loop.sh Fix all known issues in deal_joy project per CLAUDE.md. Each iteration: 1 run cd deal_joy and flutter test 2 analyze failures 3 fix code directly in deal_joy/lib/ and deal_joy/supabase/ 4 rerun tests. Follow CLAUDE.md conventions. --completion-promise "All tests passing and app ready" --max-iterations 15
```

循环会自动迭代直到所有测试通过，最多 15 轮。
