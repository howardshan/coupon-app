# DealJoy Agent 流水线（Claude Code + Pixel Agents 版）

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│  Pixel Agents 可视化层 (VS Code / Cursor 插件)              │
│  每个 Agent = 一个像素角色，实时显示 写代码/读文件/等待     │
└──────────────────────┬──────────────────────────────────────┘
                       │ 监听 JSONL transcript
┌──────────────────────▼──────────────────────────────────────┐
│  Claude Code 编排层                                          │
│                                                              │
│  /pipeline 命令 → 依次 Task 调用 6 个子代理:                │
│                                                              │
│  📋 需求解析器 → 🏗️ 架构师 → ⚙️ 后端开发                    │
│       → 🎨 前端开发 → 🔍 代码审查 → 🧪 测试工程师           │
│                                                              │
│  每个子代理 = 独立 Task = Pixel Agents 中的独立角色          │
└──────────────────────┬──────────────────────────────────────┘
                       │ 读写文件
┌──────────────────────▼──────────────────────────────────────┐
│  文件系统                                                    │
│  requirements/需求清单.xlsx → output/{模块名}/01-06 产物     │
└─────────────────────────────────────────────────────────────┘
```

## 前置要求

1. **Claude Code** (需要 Pro 或 Max 订阅，或 API Key)
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```

2. **Pixel Agents** (VS Code / Cursor 插件)
   - 在 VS Code 扩展市场搜索 "Pixel Agents" 安装
   - 或: https://marketplace.visualstudio.com/items?itemName=pablodelucca.pixel-agents
   - ⚠️ 目前仅支持 **Windows**

3. **Python 3.10+** (用于 Excel 读取脚本)
   ```bash
   pip install openpyxl
   ```

## 快速开始

### 1. 克隆项目 & 放入需求文件
```bash
cd dealjoy-cc
mkdir -p requirements
cp /path/to/DealJoy_V1_详细需求清单_v3.xlsx requirements/
```

### 2. 在 Cursor/VS Code 中打开项目
```bash
cursor dealjoy-cc
# 或
code dealjoy-cc
```

### 3. 打开 Pixel Agents 面板
- 在底部面板区域找到 "Pixel Agents" 标签
- 你会看到一个像素风格的虚拟办公室

### 4. 启动 Claude Code 终端
- 在 Pixel Agents 面板中点击 **"+ Agent"** 添加角色
- 或直接在终端中启动:
  ```bash
  claude
  ```

### 5. 运行完整流水线
在 Claude Code 中输入:
```
/pipeline 1.用户认证系统
```

你将看到:
- **主 Agent**（编排者）开始工作，Pixel 角色走到桌前
- 每调用一个子代理（Task），**新角色自动出现**
- 📋 需求解析器角色开始读取文件
- 🏗️ 架构师角色开始写代码
- 依次类推...6个角色轮流工作

### 6. 运行单个 Agent
```
/run-agent 架构师 1.用户认证系统
```

## 项目结构

```
dealjoy-cc/
├── CLAUDE.md                    # 项目上下文（Claude Code 自动读取）
├── README.md                    # 本文件
│
├── .claude/
│   ├── agents/                  # 6 个子代理定义
│   │   ├── requirement-parser.md    # 📋 需求解析器
│   │   ├── architect.md             # 🏗️ 架构师
│   │   ├── backend-coder.md         # ⚙️ 后端开发
│   │   ├── frontend-coder.md        # 🎨 前端开发
│   │   ├── reviewer.md              # 🔍 代码审查
│   │   └── test-engineer.md         # 🧪 测试工程师
│   │
│   └── commands/                # 自定义斜杠命令
│       ├── pipeline.md              # /pipeline - 完整流水线
│       └── run-agent.md             # /run-agent - 单步运行
│
├── scripts/
│   └── read_excel.py            # Excel 需求读取工具
│
├── requirements/                # 需求文件目录
│   └── (放入 Excel 文件)
│
└── output/                      # Agent 输出目录（自动创建）
    └── 1.用户认证系统/
        ├── 01_requirements.json
        ├── 02_architecture.json
        ├── 03_backend/
        ├── 04_frontend/
        ├── 05_review.json
        └── 06_tests/
```

## Agent 角色说明

| 角色 | 文件 | Pixel 中的行为 | 输入 → 输出 |
|------|------|----------------|-------------|
| 📋 需求解析器 | requirement-parser.md | 读取文件 (翻书动画) | Excel → JSON |
| 🏗️ 架构师 | architect.md | 读+写 (思考→写代码) | JSON → 架构JSON |
| ⚙️ 后端开发 | backend-coder.md | 写代码 (打字动画) | 架构 → SQL+TS |
| 🎨 前端开发 | frontend-coder.md | 写代码 (打字动画) | 架构+API → Dart |
| 🔍 代码审查 | reviewer.md | 读取文件 (审查动画) | 代码 → 报告 |
| 🧪 测试工程师 | test-engineer.md | 读+写 (测试动画) | 代码 → 测试 |

## 高级用法

### 从中间步骤继续
如果流水线中途失败，可以单独运行某个 Agent:
```
/run-agent 后端开发 1.用户认证系统
```
前提是前置步骤的输出文件已存在。

### 修改 Agent 行为
直接编辑 `.claude/agents/` 目录下的 markdown 文件。
修改后无需重启，下次调用自动生效。

### 生成其他模块
```
/pipeline 5.下单与支付
/pipeline 7.退款系统
```

## Pixel Agents 工作原理

Pixel Agents 通过监听 Claude Code 的 JSONL transcript 文件来追踪 Agent 状态:

- 当 Agent 使用 **Read** 工具 → 角色播放"阅读"动画
- 当 Agent 使用 **Write** 工具 → 角色播放"打字"动画
- 当 Agent 使用 **Bash** 工具 → 角色播放"运行命令"动画
- 当 Agent 等待输入 → 角色头顶出现气泡提示

每个 Task 子代理在 Pixel Agents 中会作为**独立角色**出现，你可以同时看到多个角色在工作。

## 注意事项

- Pixel Agents 目前仅支持 **Windows** (通过 WSL 使用 Claude Code)
- 子代理的角色可能偶尔脱同步，刷新面板即可恢复
- 建议给每个 Agent 分配不同的像素角色以便区分
