执行 DealJoy 多门店系统 Phase $ARGUMENTS。

参考完整方案文档：`/Users/howardshansmac/github/coupon app/DealJoy_多门店系统完整方案.md`
参考实施文档：`/Users/howardshansmac/github/coupon app/DealJoy_MultiStore_Complete_And_Test.md`

**先读取以上两个文档再开始写代码。**

## 执行规则

- 不要停下来问我问题，遇到不确定的自己做决定
- 如果遇到报错无法解决，记录在注释里跳过，继续下一个任务
- 不要等我确认，自动执行到底

## 路径

- 商家端：`/Users/howardshansmac/github/coupon app/coupon-app/dealjoy_merchant/`
- 用户端：`/Users/howardshansmac/github/coupon app/coupon-app/deal_joy/`
- 共享后端：`/Users/howardshansmac/github/coupon app/coupon-app/deal_joy/supabase/`

## Phase 对照表

- 1 = 注册流程改造（#7-#11）
- 2 = 角色权限 UI 控制（#18-#22）
- 3 = 登录路由逻辑（#89-#93）
- 4 = 品牌管理员功能（#28-#33）
- 5 = 邀请机制+员工管理（#23-#27, #34-#38）
- 6 = Deal多店通用（#39-#43）
- 7 = 核销逻辑改造（#44-#47）
- 8 = 结算与提现（#48-#61）
- 9 = 闭店功能（#62-#68）
- 10 = 解除品牌合作（#69-#82）
- 11 = 用户端改动（#83-#88）

## 执行步骤

### Step 1: 编码

根据实施文档中 Phase $ARGUMENTS 的待完成事项，逐项实现：
- 后端改动（Migration / Edge Function）写到共享 Supabase 目录
- 商家端代码写到 dealjoy_merchant/
- 用户端代码写到 deal_joy/（仅 Phase 11）
- UI 文案全英文，注释可中文
- 使用 ConsumerWidget + Riverpod
- 给所有新增的可交互 Widget 加 ValueKey（参考实施文档中该 Phase 的 Flutter Key 要求）

### Step 2: Build 并安装

```bash
cd "/Users/howardshansmac/github/coupon app/coupon-app/dealjoy_merchant"
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

如果 build 失败，修复编译错误后重试。

### Step 3: 用 Maestro Studio 确认实际 UI

```bash
maestro studio
```

在 Studio 中手动走一遍该 Phase 的功能流程：
- 用 Element Inspector 查看每个组件的实际文字和 ID
- 记录实际 UI 和代码中的 Key 是否匹配
- 不要跳过这一步

### Step 4: 生成 Maestro 测试脚本

在 `.maestro/flows/phase{$ARGUMENTS 补零到两位}_xxx/` 下创建 YAML 文件。

必须遵守：
- 用 ValueKey（`id:`）定位，不用显示文字
- 每个等待步骤带 `timeout: 15000`
- 多个相似按钮用 Key 或 `below:` 区分
- 需要登录的用例引用 `../shared/login.yaml`
- 非关键步骤加 `optional: true`

### Step 5: 运行 Maestro 测试

```bash
maestro test .maestro/flows/phase{对应编号}/ --format junit --output .maestro/report/phase{对应编号}/
```

### Step 6: 修复

- FAIL → 判断是代码问题还是测试脚本问题
  - 代码问题 → 修代码 → 回到 Step 2
  - 脚本问题 → 修 YAML → 回到 Step 5
- 循环直到全部 PASS

### Step 7: 输出报告

```
=== Phase $ARGUMENTS Complete ===
Features implemented: #XX - #XX
Files changed: [列出]
Test cases: X total, X passed, X failed
Known issues: [如有]
```
