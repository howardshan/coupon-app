import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/tip_payment_service.dart';

final tipPaymentServiceProvider = Provider<TipPaymentService>((ref) {
  return TipPaymentService(Supabase.instance.client);
});
