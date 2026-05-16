class AppVersionGateRow {
  const AppVersionGateRow({
    required this.appKey,
    required this.forceUpdateEnabled,
    required this.minSupportedVersion,
    this.messageTitle,
    this.messageBody,
    this.iosStoreUrl,
    this.androidStoreUrl,
  });

  final String appKey;
  final bool forceUpdateEnabled;
  final String minSupportedVersion;
  final String? messageTitle;
  final String? messageBody;
  final String? iosStoreUrl;
  final String? androidStoreUrl;

  factory AppVersionGateRow.fromJson(Map<String, dynamic> json) {
    return AppVersionGateRow(
      appKey: json['app_key'] as String? ?? '',
      forceUpdateEnabled: json['force_update_enabled'] as bool? ?? false,
      minSupportedVersion:
          json['min_supported_version'] as String? ?? '0.0.0',
      messageTitle: json['message_title'] as String?,
      messageBody: json['message_body'] as String?,
      iosStoreUrl: json['ios_store_url'] as String?,
      androidStoreUrl: json['android_store_url'] as String?,
    );
  }
}
