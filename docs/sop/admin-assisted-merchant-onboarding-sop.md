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

1. 选择 **New account**，填写商家邮箱；可选填 **Initial password**（≥8 位）；不填则系统生成一次性密码（仅在响应/页面中展示一次，请立即复制保存）。
2. 点击 **Create account only**（可选）：先创建 Auth 用户并拿到 **Target user id**，便于核对。
3. 在 **Documents** 区按类型上传文件（需已有 target user id；若未点「仅建号」，在最终提交且无证件时可直接一步 `create_user`）。
4. 填写 **Application**（公司名、联系人、电话、类别、EIN `XX-XXXXXXX`、地址等）；**联系邮箱必须与目标账号邮箱一致**。
5. 点击 **Submit application**。若本次上传了证件，系统会先隐式建号（若尚未建）再上传并 **`link_existing`** 提交，避免重复账号。

### 3.2 已有账号

1. 选择 **Existing account**，填写邮箱；**Lookup user by email** 或手动粘贴 **User ID**。
2. 上传证件（路径为 `{userId}/{document_type}/...`）。
3. 填写申请表并 **Submit application**（`link_existing`）。

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
