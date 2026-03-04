请按顺序执行以下 6 步 Agent 流水线，为 DealJoy 的 **$ARGUMENTS** 模块生成全栈代码。

**重要**：每一步都使用 Task 工具调用对应的子代理（这样 Pixel Agents 能看到每个角色）。

## 步骤 1/6: 需求解析
用 Task 调用 **需求解析器** agent：
- 先运行 `python3 scripts/read_excel.py "$ARGUMENTS"` 获取原始数据
- 将原始数据传给需求解析器
- 确认输出 `output/$ARGUMENTS/01_requirements.json`

## 步骤 2/6: 架构设计
用 Task 调用 **架构师** agent：
- 读取步骤1的输出
- 设计数据库、API、前端结构
- 确认输出 `output/$ARGUMENTS/02_architecture.json`

## 步骤 3/6: 后端开发
用 Task 调用 **后端开发** agent：
- 读取步骤2的架构设计
- 生成所有 SQL 和 Edge Function 文件
- 确认输出到 `output/$ARGUMENTS/03_backend/`

## 步骤 4/6: 前端开发
用 Task 调用 **前端开发** agent：
- 读取步骤2的架构 + 步骤3的 API 代码
- 生成所有 Flutter/Dart 文件
- 确认输出到 `output/$ARGUMENTS/04_frontend/`

## 步骤 5/6: 代码审查
用 Task 调用 **代码审查** agent：
- 审查步骤3和4的所有代码
- 如果有 P0 问题，报告并建议修复
- 输出 `output/$ARGUMENTS/05_review.json`

## 步骤 6/6: 测试生成
用 Task 调用 **测试工程师** agent：
- 根据需求和代码生成测试
- 输出到 `output/$ARGUMENTS/06_tests/`

## 完成后
汇总报告：
- 各步骤生成的文件数量
- 代码审查是否通过
- 测试覆盖情况
