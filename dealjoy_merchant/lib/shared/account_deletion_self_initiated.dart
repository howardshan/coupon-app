/// 本机正在主动调用 account-delete(full) 时置 true，忽略跨端 Realtime 登出信号
class AccountDeletionSelfInitiated {
  AccountDeletionSelfInitiated._();

  static bool active = false;
}
