# DealJoy 业务规则参考

> 所有 Agent 在做设计和编码决策时必须遵循这些业务规则。

## 核心差异化

**"Buy anytime, refund anytime"** — 无条件即时退款，这是 DealJoy 区别于 Groupon 的核心。
- Groupon: 退款需3-7个工作日
- DealJoy: 未核销的券，用户可随时发起退款，系统自动处理

## 1. 用户认证规则

### 注册
- 邮箱注册: 必填 email + password + username
- 密码要求: ≥8位，含大写+小写+数字
- Username: 2-30字符，仅字母数字下划线，全局唯一
- 邮箱验证: 注册后发送验证邮件，未验证可浏览但不能下单
- 限流: 同 IP 5次/分钟

### 第三方登录
- Google Sign-In (OAuth 2.0)
- Apple Sign-In (iOS 必须提供)
- 首次第三方登录自动创建账户 + 生成 username

### Token 管理
- Access Token: 1小时过期
- Refresh Token: 30天过期
- 多设备同时登录: 允许，最多5个设备
- 被封禁用户: 所有设备立即失效

## 2. 退款规则

### 自动退款条件（不需人工审核）
- 券码状态 = 未使用 (unused)
- 购买渠道支持自动退款 (Stripe, Apple Pay)

### 退款时间约束
- 用户提交到发起渠道退款: ≤3秒
- Stripe 到账: ≤5个工作日
- Apple Pay 到账: ≤10个工作日

### 退款失败重试
- 自动重试 5 次: 5min → 15min → 60min → 4h → 24h
- 5次失败 → P2 工单
- 72h 未解决 → P1 升级
- 最终兜底: 渠道失败 → Gift Card 余额补偿 100%

### 退款滥用检测
- 退款率 ≥50%（且 ≥5单）→ 标记可疑
- 购买后 <5min 退款 → 标记可疑
- 同 Deal 反复购退 ≥3次 → 标记可疑
- 月累计退款 ≥$500 → 人工审核
- 确认滥用 → 30天限制期

## 3. 核销规则

### 正常流程
商家扫描 → 校验券码 → 更新状态 → 通知用户 → T+1结算

### 核销失败处理
| 场景 | 处理 |
|------|------|
| 已使用 | 提示 "This voucher has already been redeemed" |
| 已退款 | 提示 "This voucher has been refunded" |
| 已过期 | 提示 "This voucher has expired" |
| 门店不匹配 | 提示 "This voucher is not valid at this location" |
| 格式无效 | 提示 "Invalid voucher code" |
| 网络超时 | 缓存请求，恢复后自动同步 |

## 4. 风控限额

### 用户交易限额
| 用户类型 | 单笔上限 | 日累计上限 | 同Deal限购 |
|----------|----------|-----------|-----------|
| 新用户 | $100 | $200 | 2张/月 |
| 普通用户 | $500 | $1,000 | 5张/月 |
| 高信用用户 | $1,000 | $3,000 | 10张/月 |

### 多账户滥用检测
- 同设备 ≥3 账户 → 标记
- 同支付方式 ≥3 账户 → 标记
- 同 IP 24h ≥5 新账户 → 拦截
- Root/越狱设备 → 高风险标记
- 模拟器 → 直接拦截

## 5. 错误码规范

所有错误码统一格式: `{MODULE}_{ERROR}`

### 认证模块
| 错误码 | 用户提示 (英文) |
|--------|-----------------|
| EMAIL_EXISTS | This email is already registered |
| WEAK_PASSWORD | Password must be at least 8 characters with uppercase, lowercase and numbers |
| USERNAME_TAKEN | This username is already taken |
| INVALID_EMAIL | Please enter a valid email address |
| INVALID_CREDENTIALS | Incorrect email or password |
| ACCOUNT_SUSPENDED | Your account has been suspended |
| ACCOUNT_BANNED | Your account has been permanently banned |
| EMAIL_NOT_VERIFIED | Please verify your email before continuing |
| RATE_LIMITED | Too many attempts. Please try again later |
| TOKEN_EXPIRED | Your session has expired. Please sign in again |
| DEVICE_LIMIT | You've reached the maximum number of devices |

### 通用错误
| 错误码 | 用户提示 (英文) |
|--------|-----------------|
| NETWORK_ERROR | Unable to connect. Please check your internet |
| INTERNAL_ERROR | Something went wrong. Please try again |
| VALIDATION_ERROR | Please check your input and try again |
| NOT_FOUND | The requested resource was not found |
| PERMISSION_DENIED | You don't have permission to do this |

## 6. 合规要求 (Dallas/Texas)

### Gift Card 相关
- Texas Business & Commerce Code §35.40-35.46
- 券码有效期: ≥5年（或无过期）
- 不得收取 dormancy/maintenance 费用
- 余额 <$2.50 可现金赎回
- DealJoy 券定位为"预付服务凭证"，遵循同等消费者保护

### 隐私 (CCPA)
- 用户有权知道、删除个人数据 (45天响应)
- 用户可 Opt-out 数据销售
- 隐私政策每 12 个月更新

### 支付 (PCI DSS)
- 不存储完整卡号（完全依赖 Stripe Token）
- TLS 1.2+ 加密传输
