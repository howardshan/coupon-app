请为 DealJoy 的 **$ARGUMENTS** 模块生成完整全栈代码。

用 Task 子代理执行，隔离上下文。

步骤：
1. 运行 `python3 scripts/read_excel.py "$ARGUMENTS"` 获取需求
2. 读取 docs/ 下所有参考文档
3. 检查 output/ 下已完成模块，保持一致性
4. 生成后端代码（SQL + Edge Functions + RLS）
5. 生成前端代码（Flutter/Dart）
6. 运行 `flutter analyze` 修复报错
7. 输出摘要

完成后提示我是否继续下一个模块。
