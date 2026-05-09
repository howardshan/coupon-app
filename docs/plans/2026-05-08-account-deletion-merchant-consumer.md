# 账户删除计划 — 文档索引（已拆分）

本主题已拆分为两份独立计划书，请直接使用：

| 文档 | 路径 |
|------|------|
| **商家端（Crunchy Plum Merchant）** | [2026-05-08-account-deletion-merchant-app.md](./2026-05-08-account-deletion-merchant-app.md) |
| **客户端（deal_joy / Crunchy Plum）** | [2026-05-08-deal-joy-account-deletion-customer.md](./2026-05-08-deal-joy-account-deletion-customer.md) |

- 两文档 **同一阶段并行开发**。  
- **`full`（整账号）**：商家端计划 **§6.1** 与客户端 **§4–§6** 为 **同一套用户级流水线**，无论从哪一端发起 `full` 须复用同一实现（`merchant_only` 不跑消费者域）。  
- **Stripe Connect**：商家删号后 **不**强制断开；商家仍可通过 **Stripe 官方**登录 Connect / Dashboard（见商家端计划 §5.6）。

> 历史：原合并版计划书内容已迁移至上述两份；后续请以对应文件为准。
