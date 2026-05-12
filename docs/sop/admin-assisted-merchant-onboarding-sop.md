# SOP：后台代商家入驻（Merchant onboard）

**适用对象**：具备 `admin` 或 `super_admin` 角色的运营人员  
**系统入口**：管理后台 `https://<你的域名>/guanli/merchants/onboard`（与 Merchants 列表页中的「Merchant onboard」链接相同）

---

## 1. 何时使用

- 商家冷启动困难、无法独立完成注册与材料上传时，由运营在取得**合法授权**后代为录入。
- 不替代 Stripe Connect、合同签署、deal 上架；仅到 **`merchants.status = pending`** 申请阶段。

---

## 2. 授权与合规

- 代填 EIN、执照等前，应取得商家授权（纸质/电子工单）。在表单 **Consent / ticket reference** 中填写可追溯编号（写入活动日志 `detail` JSON）。
- 若自动生成了登录密码，须通过安全渠道告知商家，并建议商家首次登录后修改密码。

---

## 3. 操作流程概要

### 3.1 新建账号（推荐有证件时）

1. **步骤 1 Target account**：选择 **New account**，填写商家邮箱；可选 **Initial password**（≥8 位）；不填则系统在「仅建号」或提交时生成一次性密码。
2. **步骤 2 Store type**：单店 / 连锁；连锁时填写品牌名与描述（与商家端一致）。
3. **步骤 3 Business info**：公司名、联系人、电话；**联系邮箱**与步骤 1 的邮箱一致（页面只读展示）。
4. **步骤 4 Business category**：选择类别（决定步骤 5 需要哪些证件，与商家端 `requiredDocuments` 一致）。
5. **步骤 5 EIN and documents**：填写 EIN；**须先有 target user id** 才能使用真实文件选择器——新建账号请先点 **Create account only**，已有账号请 **Lookup** 或填写 User ID。若尚未建号，页面会显示说明按钮，点击会提示原因（避免误以为「选取文件」无反应）。
6. **步骤 6 Store address**：与商家端一致——Address line 1（必填）、Address line 2（可选）、City、State、Zip（美国邮编格式）；提交时拼成与商家 App 相同的 `address` 字符串，并单独传 `city`。
7. **步骤 7 Audit**：授权工单号等；**Submit application**。

### 3.2 已有账号

1. **步骤 1**：选择 **Existing account**，填写邮箱；**Lookup user by email** 或粘贴 **User ID**。
2. 按 **3.1** 同样顺序完成步骤 2–7（步骤 5 上传前须已有 user id）。

---

## 4. 故障与重试

- **409 EMAIL_EXISTS**：该邮箱已注册；改用 **Existing account** 流程，勿重复 **Create account only**。
- **400 EMAIL_MISMATCH**：`application.contact_email` 与 `target.email` 不一致；改为同一邮箱。
- **上传失败**：确认 `SUPABASE_SERVICE_ROLE_KEY` 在网站环境可用，且 bucket `merchant-documents` 存在。
- **Edge 403**：当前登录用户不是 admin / super_admin。

---

## 5. 商家侧后续

- 商家使用**同一邮箱**登录商家端 App，应能看到 `pending` 申请及已关联材料（与自助路径一致）。
- 审批、Stripe、上架等仍在既有流程中完成。
