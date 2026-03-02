# 1.用户认证系统 - 实现计划

## 优先级 1：Bug 修复

### T1. 修复 widget_test.dart
- **文件**: `deal_joy/test/widget_test.dart`
- **改动**: 删除旧的 counter smoke test，替换为 auth 基本测试
- **原因**: 引用不存在的 MyApp，导致测试无法运行

## 优先级 2：后端补全

### T2. 数据库 Migration - 添加 username 字段
- **文件**: `deal_joy/supabase/migrations/20260301000000_add_username_to_users.sql`
- **改动**: ALTER TABLE users ADD COLUMN username TEXT UNIQUE; 更新 trigger
- **原因**: 需求 1.1.1 要求 username（2-30 字符，英文数字，唯一性验证）

## 优先级 3：Model / Repository / Provider 更新

### T3. 更新 UserModel
- **文件**: `deal_joy/lib/features/auth/data/models/user_model.dart`
- **改动**: 添加 username, updatedAt 字段
- **原因**: 与数据库字段对齐

### T4. 更新 AuthRepository
- **文件**: `deal_joy/lib/features/auth/data/repositories/auth_repository.dart`
- **改动**:
  - signUpWithEmail 增加 username 参数
  - 添加 signInWithGoogle() 完整实现
  - 添加 signInWithApple() 方法
  - 添加 resendVerificationEmail() 方法
  - 添加 updatePassword() 方法（用于重置密码页面）
  - resetPassword 统一错误处理（不泄露邮箱存在性）
- **原因**: 支持新增的注册字段和完整的认证流程

### T5. 更新 AuthProvider
- **文件**: `deal_joy/lib/features/auth/domain/providers/auth_provider.dart`
- **改动**:
  - signUp 增加 username 参数
  - 添加 signInWithGoogle() 方法
  - 添加 signInWithApple() 方法
  - 添加 forgotPasswordProvider (Notifier 模式替代 setState)
- **原因**: 支持 UI 层新增的功能

## 优先级 4：UI 修改

### T6. 重写 RegisterScreen
- **文件**: `deal_joy/lib/features/auth/presentation/screens/register_screen.dart`
- **改动**:
  - 添加 Username 字段（2-30 字符，字母数字验证）
  - 添加 Confirm Password 字段（实时匹配验证）
  - 密码验证改为 min 8，要求大小写+数字
  - 添加密码强度指示器（Weak/Medium/Strong）
  - 添加 Terms of Service 复选框
  - 注册成功显示 "Verification email sent!" 提示
  - 更好的邮箱格式验证（regex）
- **原因**: 需求 1.1.1 完整注册表单

### T7. 更新 LoginScreen
- **文件**: `deal_joy/lib/features/auth/presentation/screens/login_screen.dart`
- **改动**:
  - 添加 "Keep me signed in for 30 days" 复选框
  - 添加 Google/Apple 登录按钮（"or continue with" 分隔线）
  - 邮箱验证增强（proper regex）
  - 密码验证 min 8 chars
  - 统一错误消息 "Invalid email or password"
- **原因**: 需求 1.2.1 + 1.2.2

### T8. 重写 ForgotPasswordScreen
- **文件**: `deal_joy/lib/features/auth/presentation/screens/forgot_password_screen.dart`
- **改动**:
  - 改用 Riverpod 状态管理（去掉 setState）
  - 隐私安全消息："If this email is registered, you'll receive a reset link."
  - 添加返回登录链接
  - 添加重发冷却计时器（60s）
- **原因**: 需求 1.3.1 + 代码一致性

### T9. 新建 ResetPasswordScreen
- **文件**: `deal_joy/lib/features/auth/presentation/screens/reset_password_screen.dart`
- **改动**: 全新页面
  - 新密码 + 确认密码
  - 密码强度指示器
  - 成功后 3 秒跳转登录页
  - 错误处理（链接过期/已使用/无效）
- **原因**: 需求 1.3.2

### T10. 新建密码强度指示器 Widget
- **文件**: `deal_joy/lib/features/auth/presentation/widgets/password_strength_indicator.dart`
- **改动**: 全新可复用组件
  - 计算密码强度：Weak/Medium/Strong
  - 颜色进度条 + 文字标签
- **原因**: 注册和重置密码页面都需要

## 优先级 5：路由 + 集成

### T11. 更新路由配置
- **文件**: `deal_joy/lib/core/router/app_router.dart`
- **改动**:
  - 添加 /auth/reset-password 路由（带 token 参数）
- **原因**: 支持新增的重置密码页面

## 优先级 6：测试

### T12. 编写 Auth 测试
- **文件**: `deal_joy/test/features/auth/` 目录下
- **改动**: 为修改的功能编写单元测试
- **原因**: 确保代码正确性

## 已知限制（V1 不实现）
- 登录失败计数 + 验证码 + 账户锁定（需要服务端状态表）
- 邮箱验证深链接处理（需要平台配置）
- 登录 IP/设备记录（需要服务端）
- Facebook 登录（需求明确为 V2）
- 多设备同时登录管理
