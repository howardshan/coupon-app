/// 本机正在主动调用整账号删除 Edge 时置 true，用于忽略同源 Realtime 登出信号（避免重复弹窗）
class AccountDeletionSelfInitiated {
  AccountDeletionSelfInitiated._();

  static bool active = false;
}
