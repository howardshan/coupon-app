请按顺序执行以下 6 步 Agent 流水线，为 DealJoy **商家端** 的 **$ARGUMENTS** 模块生成全栈代码。

**重要**：这是商家端模块，需求来源为商家端需求清单 Excel，UI 参考为 merchant-reference.md。

## 步骤 1/6: 需求解析
用 Task 调用 **需求解析器** agent：
- 先运行 `python3 scripts/read_merchant_excel.py "$ARGUMENTS"` 获取原始数据
- 将原始数据传给需求解析器
- 提示解析器：这是**商家端**模块，端=商家端
- 确认输出 `output/merchant/$ARGUMENTS/01_requirements.json`

## 步骤 2/6: 架构设计
用 Task 调用 **架构师** agent：
- 读取步骤1的输出
- **必须先读** `docs/ui/merchant-reference.md` 了解商家端页面布局
- 设计数据库、API、前端结构
- 确认输出 `output/merchant/$ARGUMENTS/02_architecture.json`

## 步骤 3/6: 后端开发
用 Task 调用 **后端开发** agent：
- 读取步骤2的架构设计
- 注意：商家端的 RLS 策略需要基于 merchant role，不是普通 user
- 生成所有 SQL 和 Edge Function 文件
- 确认输出到 `output/merchant/$ARGUMENTS/03_backend/`

## 步骤 4/6: 前端开发
用 Task 调用 **前端开发** agent：
- **必须先读** `docs/ui/merchant-reference.md`
- 读取步骤2的架构 + 步骤3的 API 代码
- 商家端前端结构: `lib/features/merchant/{module}/`
- 确认输出到 `output/merchant/$ARGUMENTS/04_frontend/`

## 步骤 5/6: 代码审查
用 Task 调用 **代码审查** agent：
- 审查步骤3和4的所有代码
- **额外检查**: 商家端 RLS 是否正确隔离（商家只能看自己门店的数据）
- 输出 `output/merchant/$ARGUMENTS/05_review.json`

## 步骤 6/6: 测试生成
用 Task 调用 **测试工程师** agent：
- 根据需求和代码生成测试
- **额外测试**: 跨商家数据隔离测试
- 输出到 `output/merchant/$ARGUMENTS/06_tests/`

## 完成后
汇总报告各步骤文件数和审查结果。
