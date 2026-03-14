# DealJoy Widget Key 对照表

> 本次共添加 **81 个 ValueKey**（deal_joy 34 个 + dealjoy_merchant 47 个）
> 命名规则：`页面缩写_功能_btn/field`

---

## 客户端（deal_joy）— 34 个 Key

### Auth 模块

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `login_email_field` | AppTextField | auth/screens/login_screen.dart | 登录邮箱输入 |
| `login_password_field` | AppTextField | auth/screens/login_screen.dart | 登录密码输入 |
| `login_forgot_password_btn` | TextButton | auth/screens/login_screen.dart | 忘记密码链接 |
| `login_signup_btn` | TextButton | auth/screens/login_screen.dart | 跳转注册页 |
| `register_email_field` | AppTextField | auth/screens/register_screen.dart | 注册邮箱输入 |
| `register_password_field` | AppTextField | auth/screens/register_screen.dart | 注册密码输入 |
| `register_confirm_password_field` | AppTextField | auth/screens/register_screen.dart | 确认密码输入 |
| `register_username_field` | AppTextField | auth/screens/register_screen.dart | 用户名输入 |
| `register_full_name_field` | AppTextField | auth/screens/register_screen.dart | 全名输入 |
| `forgot_password_email_field` | AppTextField | auth/screens/forgot_password_screen.dart | 找回密码邮箱 |
| `reset_password_field` | AppTextField | auth/screens/reset_password_screen.dart | 新密码输入 |
| `reset_confirm_password_field` | AppTextField | auth/screens/reset_password_screen.dart | 确认新密码 |

### Home / Search 模块

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `home_search_field` | TextField | deals/screens/home_screen.dart | 首页搜索框 |
| `search_keyword_field` | TextField | deals/screens/search_screen.dart | 搜索关键词输入 |
| `search_retry_btn` | TextButton | deals/screens/search_screen.dart | 搜索错误重试 |
| `search_reset_filters_btn` | TextButton | deals/screens/search_screen.dart | 重置筛选条件 |
| `search_apply_filters_btn` | ElevatedButton | deals/screens/search_screen.dart | 应用筛选条件 |

### Checkout 模块

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `checkout_coupon_field` | TextField | checkout/screens/checkout_screen.dart | 优惠码输入框 |
| `checkout_apply_coupon_btn` | ElevatedButton | checkout/screens/checkout_screen.dart | 应用优惠码 |
| `checkout_change_payment_btn` | TextButton | checkout/screens/checkout_screen.dart | 更换支付方式 |
| `checkout_retry_btn` | ElevatedButton | checkout/screens/checkout_screen.dart | 支付失败重试 |

### Orders / Coupons 模块

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `coupon_retry_btn` | ElevatedButton | orders/screens/coupon_screen.dart | 优惠券加载重试 |
| `coupon_refund_cancel_btn` | TextButton | orders/screens/coupon_screen.dart | 取消退款 |
| `coupon_refund_confirm_btn` | ElevatedButton | orders/screens/coupon_screen.dart | 确认退款 |
| `coupon_gift_cancel_btn` | TextButton | orders/screens/coupon_screen.dart | 取消赠送 |
| `coupon_send_gift_btn` | ElevatedButton | orders/screens/coupon_screen.dart | 发送礼物 |
| `coupons_retry_btn` | ElevatedButton | orders/screens/coupons_screen.dart | 优惠券列表重试 |

### Merchant / Store 模块

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `brand_detail_retry_btn` | ElevatedButton | merchant/screens/brand_detail_screen.dart | 品牌详情重试 |
| `store_buy_now_btn` | ElevatedButton | merchant/widgets/store_bottom_bar.dart | 立即购买 |
| `store_view_deal_btn` | ElevatedButton | merchant/widgets/store_bottom_bar.dart | 查看 Deal |

### Reviews 模块

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `review_comment_field` | TextField | reviews/screens/write_review_screen.dart | 评价内容输入 |

### Deal 详情页（新增 2 个）

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `deal_image_gallery` | IconButton | deals/screens/deal_detail_screen.dart | 查看全部图片按钮 |
| `deal_variant_selector` | Widget | deals/screens/deal_detail_screen.dart | 同商家套餐横向选择器 |

### Core

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `scaffold_resend_otp_btn` | TextButton | core/widgets/main_scaffold.dart | 重发验证码 |

---

## 商家端（dealjoy_merchant）— 47 个新增 Key + 6 个已有 Key

### 已有 Key（本次未修改）

| Key 名称 | Widget 类型 | 文件 |
|----------|-----------|------|
| `login_email_field` | TextFormField | merchant_auth/merchant_login_page.dart |
| `login_password_field` | TextFormField | merchant_auth/merchant_login_page.dart |
| `login_submit_btn` | ElevatedButton | merchant_auth/merchant_login_page.dart |
| `register_submit_btn` / `register_next_btn` | ElevatedButton | merchant_auth/merchant_register_page.dart |
| `staff_invite_email_field` | TextField | store/staff_manage_page.dart |
| `earnings_view_all_transactions_btn` | TextButton | earnings/earnings_page.dart |

### Auth 模块（新增 3 个）

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `review_status_dashboard_btn` | ElevatedButton | merchant_auth/merchant_review_status_page.dart | 跳转 Dashboard |
| `review_status_resubmit_btn` | ElevatedButton | merchant_auth/merchant_review_status_page.dart | 重新提交注册 |
| `review_status_retry_btn` | ElevatedButton | merchant_auth/merchant_review_status_page.dart | 加载重试 |

### Store / Brand 模块（新增 15 个）

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `store_edit_save_btn` | ElevatedButton | store/store_edit_page.dart | 保存店铺信息 |
| `store_edit_name_field` | TextFormField | store/store_edit_page.dart | 店铺名称 |
| `store_edit_desc_field` | TextFormField | store/store_edit_page.dart | 店铺描述 |
| `store_edit_phone_field` | TextFormField | store/store_edit_page.dart | 店铺电话 |
| `store_edit_address_field` | TextFormField | store/store_edit_page.dart | 店铺地址 |
| `business_hours_save_btn` | ElevatedButton | store/business_hours_page.dart | 保存营业时间 |
| `store_tags_save_btn` | ElevatedButton | store/store_tags_page.dart | 保存标签 |
| `brand_info_save_btn` | ElevatedButton | store/brand_info_page.dart | 保存品牌信息 |
| `brand_info_name_field` | TextFormField | store/brand_info_page.dart | 品牌名称 |
| `brand_info_desc_field` | TextFormField | store/brand_info_page.dart | 品牌描述 |
| `brand_admin_invite_submit_btn` | ElevatedButton | store/brand_admins_page.dart | 邀请管理员提交 |
| `brand_admin_email_field` | TextField | store/brand_admins_page.dart | 管理员邮箱 |
| `brand_store_add_submit_btn` | ElevatedButton | store/brand_stores_page.dart | 添加门店提交 |
| `brand_store_add_email_field` | TextField | store/brand_stores_page.dart | 门店邮箱 |
| `header_style_save_btn` | ElevatedButton | store/widgets/header_style_selector.dart | 保存头部样式 |

### Deal 模块（新增 18 个）

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `deal_create_submit_btn` | ElevatedButton | deals/deal_create_page.dart | 创建 Deal 提交 |
| `deal_create_title_field` | TextFormField | deals/deal_create_page.dart | Deal 标题 |
| `deal_create_desc_field` | TextFormField | deals/deal_create_page.dart | Deal 描述 |
| `deal_create_usage_notes_field` | TextFormField | deals/deal_create_page.dart | 使用说明 |
| `deal_create_discount_price_field` | TextFormField | deals/deal_create_page.dart | 折扣价 |
| `deal_create_stock_field` | TextFormField | deals/deal_create_page.dart | 库存数量 |
| `deal_create_validity_days_field` | TextFormField | deals/deal_create_page.dart | 有效天数 |
| `deal_create_max_per_person_field` | TextFormField | deals/deal_create_page.dart | 每人限购数 |
| `deal_edit_submit_btn` | ElevatedButton | deals/deal_edit_page.dart | 编辑 Deal 提交 |
| `deal_edit_title_field` | TextFormField | deals/deal_edit_page.dart | Deal 标题 |
| `deal_edit_desc_field` | TextFormField | deals/deal_edit_page.dart | Deal 描述 |
| `deal_edit_usage_notes_field` | TextFormField | deals/deal_edit_page.dart | 使用说明 |
| `deal_edit_discount_price_field` | TextFormField | deals/deal_edit_page.dart | 折扣价 |
| `deal_edit_stock_field` | TextFormField | deals/deal_edit_page.dart | 库存数量 |
| `deal_edit_validity_days_field` | TextFormField | deals/deal_edit_page.dart | 有效天数 |
| `deal_edit_max_per_person_field` | TextFormField | deals/deal_edit_page.dart | 每人限购数 |
| `deal_detail_toggle_active_btn` | ElevatedButton | deals/deal_detail_page.dart | 激活/停用 Deal |
| `deal_detail_delete_btn` | ElevatedButton | deals/deal_detail_page.dart | 删除 Deal |

### Deal 确认 / 列表（新增 4 个 + 2 个）

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `deal_confirm_retry_btn` | ElevatedButton | deals/store_deal_confirm_page.dart | 确认页重试 |
| `deal_confirm_accept_btn` | ElevatedButton | deals/store_deal_confirm_page.dart | 接受品牌 Deal |
| `deals_list_new_category_field` | TextField | deals/deals_list_page.dart | 新建分类名 |
| `deals_list_edit_category_field` | TextField | deals/deals_list_page.dart | 编辑分类名 |
| `deal_short_name_field` | TextFormField | deals/deal_create_page.dart, deal_edit_page.dart | Deal 简称输入（≤10字符） |
| `deal_list_drag_handle` | Icon | deals/deals_list_page.dart | 拖拽排序手柄 |

### Scan 模块（新增 3 个）

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `scan_verify_btn` | ElevatedButton | scan/scan_page.dart | 手动验证券码 |
| `scan_code_field` | TextFormField | scan/scan_page.dart | 券码输入框 |
| `redemption_done_btn` | ElevatedButton | scan/redemption_success_page.dart | 核销完成返回 |

### Earnings 模块（新增 4 个）

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `withdrawal_confirm_btn` | ElevatedButton | earnings/withdrawal_page.dart | 确认提现 |
| `withdrawal_amount_field` | TextField | earnings/withdrawal_page.dart | 提现金额 |
| `transactions_apply_filter_btn` | ElevatedButton | earnings/transactions_page.dart | 应用交易筛选 |
| `earnings_report_retry_btn` | ElevatedButton | earnings/earnings_report_page.dart | 报表重试 |

### Settings 模块（新增 2 个）

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `settings_confirm_btn` | ElevatedButton | settings/settings_page.dart | 设置确认 |
| `settings_brand_name_field` | TextField | settings/settings_page.dart | 品牌名称输入 |

### Menu 模块（新增 5 个）

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `menu_picker_confirm_btn` | ElevatedButton | menu/widgets/menu_item_picker.dart | 菜品选择确认 |
| `menu_new_category_field` | TextField | menu/category_manage_page.dart | 新建分类名 |
| `menu_edit_category_field` | TextField | menu/category_manage_page.dart | 编辑分类名 |
| `menu_edit_name_field` | TextFormField | menu/menu_edit_page.dart | 菜品名称 |
| `menu_edit_price_field` | TextFormField | menu/menu_edit_page.dart | 菜品价格 |

### Dashboard（新增 1 个）

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `brand_overview_retry_btn` | ElevatedButton | dashboard/brand_overview_page.dart | 品牌总览重试 |

### Reviews（新增 2 个）

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `reply_submit_btn` | ElevatedButton | reviews/widgets/reply_bottom_sheet.dart | 提交回复 |
| `reply_content_field` | TextField | reviews/widgets/reply_bottom_sheet.dart | 回复内容 |

### Notification（新增 1 个）

| Key 名称 | Widget 类型 | 文件 | 功能 |
|----------|-----------|------|------|
| `notification_retry_btn` | ElevatedButton | settings/notification_preferences_page.dart | 通知偏好重试 |
