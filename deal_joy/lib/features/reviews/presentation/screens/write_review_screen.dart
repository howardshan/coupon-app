import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/domain/providers/auth_provider.dart';

class WriteReviewScreen extends ConsumerStatefulWidget {
  final String dealId;

  const WriteReviewScreen({super.key, required this.dealId});

  @override
  ConsumerState<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends ConsumerState<WriteReviewScreen> {
  double _rating = 4.0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      final client = ref.read(supabaseClientProvider);
      await client.from('reviews').insert({
        'deal_id': widget.dealId,
        'user_id': user.id,
        'rating': _rating.toInt(),
        'comment': _commentCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review submitted!'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Write a Review')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your Rating',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            RatingBar.builder(
              initialRating: _rating,
              minRating: 1,
              itemBuilder: (_, _) =>
                  const Icon(Icons.star, color: AppColors.featuredBadge),
              onRatingUpdate: (r) => setState(() => _rating = r),
            ),
            const SizedBox(height: 24),
            const Text('Your Review',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _commentCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText:
                    'Share your experience — food, service, atmosphere...',
              ),
            ),
            const SizedBox(height: 32),
            AppButton(
              label: 'Submit Review',
              isLoading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
