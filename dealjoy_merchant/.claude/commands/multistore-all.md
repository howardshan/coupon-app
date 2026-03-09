依次执行 DealJoy 多门店系统全部 11 个 Phase。

**规则：**
- 每个 Phase 完成后输出一行进度报告，然后立即开始下一个
- 不要停下来问我问题，遇到不确定的自己做决定
- 遇到报错无法解决的，记录后跳过继续下一个
- 每个 Phase 做完必须跑 Maestro 测试

参考文档：
- 完整方案：`/Users/howardshansmac/github/coupon app/DealJoy_多门店系统完整方案.md`
- 实施文档：`/Users/howardshansmac/github/coupon app/DealJoy_MultiStore_Complete_And_Test.md`

**先读取以上两个文档。**

按以下顺序逐个执行（每个 Phase 的详细内容参考实施文档）：

## Phase 1: 注册流程改造（#7-#11）
1. 注册页添加 Single/Multiple Location 选择
2. Multiple → 品牌信息填写 → 第一家门店 → 提交审核
3. 设置页添加 Upgrade to Chain
4. 加 ValueKey → build APK → maestro studio 确认 UI → 写测试 → 跑测试 → 修到全过

## Phase 2: 角色权限 UI 控制（#18-#22）
1. app_shell.dart 根据 permissions 动态控制 Bottom Nav tab
2. 创建权限 Provider
3. 加 ValueKey → build → studio → 测试 → 修到全过

## Phase 3: 登录路由逻辑（#89-#93）
1. 登录后按角色分流（品牌管理员/门店老板/员工/审核中/新用户）
2. 加 ValueKey → build → studio → 测试 → 修到全过

## Phase 4: 品牌管理员功能（#28-#33）
1. 门店切换器 Widget
2. X-Merchant-Id header
3. 品牌管理页（品牌信息+门店列表+管理员列表）
4. 添加门店（直接创建/邀请）
5. 加 ValueKey → build → studio → 测试 → 修到全过

## Phase 5: 邀请机制 + 员工管理（#23-#27, #34-#38）
1. invite/update/remove API 补全
2. 品牌邀请管理员/门店 API
3. 员工管理页面
4. 角色创建权限校验
5. 加 ValueKey → build → studio → 测试 → 修到全过

## Phase 6: Deal 多店通用（#39-#43）
1. deal_applicable_stores 表
2. 创建 Deal 时选适用门店
3. 用户端展示适用门店列表
4. 加 ValueKey → build → studio → 测试 → 修到全过

## Phase 7: 核销逻辑改造（#44-#47）
1. 核销校验 deal_applicable_stores
2. orders.redeemed_merchant_id
3. 错误提示
4. 加 ValueKey → build → studio → 测试 → 修到全过

## Phase 8: 结算与提现（#48-#61）
1. 结算给 redeemed_merchant_id
2. T+7 可提现余额
3. 提现页面（仅门店老板可操作）
4. Stripe Connect 集成
5. 加 ValueKey → build → studio → 测试 → 修到全过

## Phase 9: 闭店功能（#62-#68）
1. 闭店前处理（自动退款+结算+提示提现）
2. 状态变 Closed
3. 连锁店闭店脱离品牌
4. 加 ValueKey → build → studio → 测试 → 修到全过

## Phase 10: 解除品牌合作（#69-#82）
1. Leave Brand / Remove Store
2. 品牌通用 Deal 移除门店
3. 用户通知 + Request Refund
4. 无适用门店自动全退
5. 加 ValueKey → build → studio → 测试 → 修到全过

## Phase 11: 用户端改动（#83-#88）
1. 搜索品牌名
2. 详情页品牌标识
3. Other Locations
4. Deal 显示适用门店
5. 券面标注
6. build 用户端 → 测试

## 完成后

1. 跑全量测试：
```bash
maestro test .maestro/flows/ --format junit --output .maestro/report/full/
```

2. 用 python3 + openpyxl 生成测试报告 Excel：
`/Users/howardshansmac/github/coupon app/DealJoy_MultiStore_Test_Report.xlsx`

3. 输出汇总：
```
=== DealJoy Multi-Store System Complete ===
Total Features: 93
Implemented: XX/93
Test Cases: XX
Passed: XX
Failed: XX
Pass Rate: XX%
```
