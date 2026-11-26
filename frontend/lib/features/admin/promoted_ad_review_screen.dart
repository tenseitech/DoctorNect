import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/models/promoted_ad_model.dart';
import '../../core/supabase/supabase_bootstrap.dart';
import '../../core/supabase/supabase_stream_table.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Lists `pending_approval` ads for a super admin already inside the portal.
/// `reviewPromotedAd` rejects every other caller.
class PromotedAdReviewScreen extends StatefulWidget {
  const PromotedAdReviewScreen({super.key});

  @override
  State<PromotedAdReviewScreen> createState() => _PromotedAdReviewScreenState();
}

class _PromotedAdReviewScreenState extends State<PromotedAdReviewScreen> {
  String? _busyAdId;

  Stream<List<PromotedAdModel>>? get _pending {
    if (!SupabaseBootstrap.isReady) return null;
    if (SupabaseBootstrap.isProduction) {
      return streamTable(
        table: 'promoted_ads',
        primaryKey: ['ad_id'],
        filterColumn: 'status',
        filterValue: 'pending_approval',
      ).map((rows) => rows.map(PromotedAdModel.fromRow).toList());
    }
    return SupabaseBootstrap.client
        .from('promoted_ads')
        .stream(primaryKey: ['ad_id'])
        .eq('status', 'pending_approval')
        .map((rows) => rows.map(PromotedAdModel.fromRow).toList());
  }

  Future<void> _review(String adId, String decision) async {
    setState(() => _busyAdId = adId);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('reviewPromotedAd')
          .call({'adId': adId, 'decision': decision});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(decision == 'approve' ? 'Ad approved' : 'Ad rejected'),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Could not review this ad')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not review this ad')),
      );
    } finally {
      if (mounted) setState(() => _busyAdId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Promoted ads',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: AppTypography.titleMedium,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: pending == null
          ? const Center(child: Text('Database connection is not ready.'))
          : StreamBuilder<List<PromotedAdModel>>(
              stream: pending,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(
                    child: Text('Could not load ads pending approval.'),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final ads = snap.data!;
                if (ads.isEmpty) {
                  return const Center(
                    child: Text('No ads are waiting for approval.'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: ads.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final ad = ads[index];
                    final busy = _busyAdId == ad.adId;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ad.title,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${ad.providerType} · ${ad.durationHours}h · ₹${ad.amountPaid}',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                FilledButton(
                                  onPressed: busy
                                      ? null
                                      : () => _review(ad.adId, 'approve'),
                                  child: const Text('Approve'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => _review(ad.adId, 'reject'),
                                  child: const Text('Reject'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
