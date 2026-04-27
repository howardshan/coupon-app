/// Post-redemption tip: data returned with successful redeem (merchant-scan).
class TipDealConfig {
  const TipDealConfig({
    required this.tipsEnabled,
    this.tipsMode,
    this.preset1,
    this.preset2,
    this.preset3,
    required this.tipBaseCents,
  });

  final bool tipsEnabled;
  final String? tipsMode;
  final double? preset1;
  final double? preset2;
  final double? preset3;
  final int tipBaseCents;

  factory TipDealConfig.fromRedeemPayload(Map<String, dynamic> json) {
    final deal = json['deal'] as Map<String, dynamic>? ?? {};
    return TipDealConfig(
      tipsEnabled: deal['tips_enabled'] as bool? ?? false,
      tipsMode: deal['tips_mode'] as String?,
      preset1: (deal['tips_preset_1'] as num?)?.toDouble(),
      preset2: (deal['tips_preset_2'] as num?)?.toDouble(),
      preset3: (deal['tips_preset_3'] as num?)?.toDouble(),
      tipBaseCents: (json['tip_base_cents'] as num?)?.toInt() ?? 0,
    );
  }
}

class RedeemResult {
  const RedeemResult({
    required this.redeemedAt,
    required this.tip,
  });

  final DateTime redeemedAt;
  final TipDealConfig tip;
}
