# DealJoy 多门店 Pipeline 安装指南

## 文件说明

```
multistore_pipeline/
├── multistore-phase.md        → 复制到 dealjoy_merchant/.claude/commands/
├── multistore-all.md          → 复制到 dealjoy_merchant/.claude/commands/
└── shared/
    └── login.yaml             → 复制到 dealjoy_merchant/.maestro/shared/
```

## 安装步骤

### 1. 复制 pipeline 命令到商家端项目

```bash
# 进入商家端项目
cd "/Users/howardshansmac/github/coupon app/coupon-app/dealjoy_merchant"

# 确保目录存在
mkdir -p .claude/commands
mkdir -p .maestro/shared
mkdir -p .maestro/flows
mkdir -p .maestro/report

# 从下载的文件复制（根据你放的位置调整路径）
cp multistore-phase.md .claude/commands/
cp multistore-all.md .claude/commands/
cp shared/login.yaml .maestro/shared/
```

### 2. 确保方案文档在 coupon app/ 目录下

```bash
ls "/Users/howardshansmac/github/coupon app/DealJoy_多门店系统完整方案.md"
ls "/Users/howardshansmac/github/coupon app/DealJoy_MultiStore_Complete_And_Test.md"
```

### 3. 确保 Maestro 已安装

```bash
maestro --version
# 如果没装：curl -fsSL "https://get.maestro.mobile.dev" | bash
```

### 4. 确保 Android 模拟器在运行

```bash
adb devices
# 应该看到一个设备
```

## 使用方式

### 方式A: 一次跑全部11个 Phase（可能会中断）

在商家端目录的 Claude Code 中执行：
```
/multistore-all
```

### 方式B: 逐个 Phase 执行（推荐，更稳定）

```
/multistore-phase 1
```
等完成后：
```
/multistore-phase 2
```
以此类推到 11。

### 方式C: 如果中断了，恢复执行

```
/multistore-phase 4
```
（从断掉的 Phase 继续，前面的不会重复）

## Maestro 配置

创建 `.maestro/config.yaml`：
```yaml
appId: com.dealjoy.merchant
onFlowStart:
  - clearState
  - launchApp
```

确认 appId 和你的商家端 App 包名一致。查包名：
```bash
grep "applicationId" android/app/build.gradle
```
