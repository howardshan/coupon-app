# 商家入驻信息采集表（代运营录入用）

**用途**：商家或商务在取得平台代填授权后，按本表提供信息；运营人员将内容录入管理后台 **Admin-assisted onboarding**（`/guanli/merchants/onboard`）。  
**内部操作说明**：参见 [SOP：后台代商家入驻](../sop/admin-assisted-merchant-onboarding-sop.md)。  
**其他语言 / 格式**：[English](./merchant-assisted-onboarding-intake-en.md) · [CSV/Excel 模版](./merchant-assisted-onboarding-intake-template.csv)（UTF-8 BOM，可用 Excel 打开）

---

## 填写说明

- 请使用 **英文或拼音** 填写后台与系统一致的字段（公司名、地址等可按证照原文；**类目**请从下表勾选与后台完全一致的英文枚举值）。
- **登录邮箱** 将用作商家端账号与联系邮箱，二者须一致。
- 证件请准备 **PDF 或 JPG/PNG/WebP**；后台按类目逐项上传，名称请与本表「证件代码」列一致，便于运营核对。
- **美国地址** 请按行填写；邮编为 5 位或 ZIP+4（如 `75201` 或 `75201-1234`）。

---

## A. 账号方式（二选一）

| 项目 | 填写 |
|------|------|
| □ 新建账号（create_user） / □ 已有账号（link_existing） | |
| **登录邮箱**（必填） | |
| 若为新建：是否由商家自行设定初始密码（≥8 位）？若否，将由系统生成一次性密码并由安全渠道告知。 | □ 商家提供初始密码：______________ / □ 由系统生成 |
| 若为已有账号：**Supabase User ID**（若不知，可提供邮箱由运营 Lookup） | |

---

## B. 门店类型

| 项目 | 填写 |
|------|------|
| □ 单店（single） / □ 连锁或品牌（multiple） | |
| 若为连锁：**品牌名称**（可选） | |
| **品牌描述**（可选） | |

---

## C. 经营信息

| 项目 | 填写 |
|------|------|
| **公司法定名称**（Company name） | |
| **联系人姓名**（Contact name） | |
| **电话**（Phone，建议含区号） | |

（联系邮箱与 **A. 登录邮箱** 相同，无需重复填写。）

---

## D. 经营类目（请只选一项，与后台下拉一致）

在下列 **英文值** 中圈选一项：

`Restaurant` · `SpaAndMassage` · `HairAndBeauty` · `Fitness` · `FunAndGames` · `NailAndLash` · `Wellness` · `Other`

**所选类目**：________________

---

## E. EIN 与证件清单

### E1. EIN / 税号

格式示例：`12-3456789`

| **EIN / Tax ID** | |
|------------------|---|

### E2. 按类目须提供的材料

**所有类目**均须包含以下 4 项（后台字段 `apiValue` 见括号）：

| 序号 | 证件（后台代码） | 商家提供文件名或说明 |
|------|------------------|----------------------|
| 1 | 营业执照（`business_license`） | |
| 2 | 店主/法人身份证明（`owner_id`） | |
| 3 | 店面照片（`storefront_photo`） | |
| 4 | 一般责任险（`liability_insurance`） | |

**按所选类目 D 额外须提供**（仅勾选与所选类目相关的行）：

| 类目 | 额外证件（后台代码） |
|------|----------------------|
| Restaurant | `health_permit`（卫生许可） · `food_service_license`（食品经营许可） |
| SpaAndMassage | `health_permit` · `cosmetology_license`（美容执照） · `massage_therapy_license`（按摩治疗执照） |
| HairAndBeauty | `cosmetology_license` |
| Fitness | `facility_license`（场馆许可） |
| NailAndLash | `health_permit` · `cosmetology_license` |
| Wellness | `massage_therapy_license` |
| Other | `general_business_permit`（一般营业许可） |
| FunAndGames | （无额外项，仅上述 4 项基础材料） |

**本商家额外材料行（可复制多行）**：

| 后台代码 | 文件说明 |
|----------|----------|
| | |

---

## F. 门店地址（美国）

| 项目 | 填写 |
|------|------|
| **Address line 1**（必填，门牌街道） | |
| Address line 2（可选，套房单元等） | |
| **City** | |
| **State**（2 位州缩写，如 TX） | |
| **Zip code**（5 位或 ZIP+4） | |

---

## G. 授权与内部备注（运营录入 Audit）

| 项目 | 填写 |
|------|------|
| **授权 / 工单编号**（对应后台 *Consent / ticket reference*，须可追溯） | |
| 内部备注（对应后台 *Internal note*，可选） | |

---

## H. 确认签字（可选，视公司流程）

本人确认已授权 ________________（平台名称）代为在系统中提交上述信息及证照，所提供材料真实有效。

商家签字：______________ 日期：______________  
（或电子工单编号：______________）

---

## 运营回填检查清单（录入前打勾）

- [ ] 邮箱与已有账号策略一致（新建 / 已有，无 409 重复建号误操作）
- [ ] 类目与证件清单一一对应，文件齐全
- [ ] 地址与邮编格式符合美国规则
- [ ] **Consent / ticket reference** 已填写
- [ ] 新建账号若生成一次性密码，已安排安全渠道交付商家

---

*文档版本：与 2026-05 管理端代入驻表单字段对齐；若后台字段变更，请同步更新本模板、英文版及 CSV 模版。*
