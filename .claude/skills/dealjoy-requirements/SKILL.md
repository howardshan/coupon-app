---
name: dealjoy-requirements
description: "DealJoy 需求解析。当任务涉及从 Excel 需求清单开发新模块时自动触发。"
invocation: auto
---

# DealJoy 需求解析

## 何时触发
当用户提到开发某个模块（如"用户认证系统"、"商品管理"等），且需要从需求清单获取详情时。

## 工作流程

### 1. 读取需求
```bash
python3 scripts/read_excel.py "<模块名>"
```

### 2. 解析为结构化需求
将 Excel 原始数据解析为：
- 功能点列表（每个功能点含子项、业务规则、异常场景）
- 非功能需求（性能、安全）
- 功能间依赖关系

### 3. 保存需求文档
输出到 `.pipeline/<模块名>/01_requirements.json`

### 4. 对照现有代码
读取 `deal_joy/lib/features/` 查看哪些已实现、哪些需要新建或修改。

## 输出格式
```json
{
  "module_name": "用户认证系统",
  "existing_files": ["已存在的文件列表"],
  "功能点列表": [
    {
      "id": "1.1.1",
      "name": "基本注册",
      "description": "...",
      "子项": [],
      "业务规则": [],
      "异常场景": [],
      "implemented": false
    }
  ]
}
```
