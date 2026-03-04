运行 DealJoy 流水线中的单个 Agent。

用法: `/run-agent <agent名称> <模块名>`
示例: `/run-agent 架构师 1.用户认证系统`

请根据 $ARGUMENTS 解析出 agent 名称和模块名，然后用 Task 调用对应的子代理。

可用的 Agent: 需求解析器, 架构师, 后端开发, 前端开发, 代码审查, 测试工程师
