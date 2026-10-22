import 'package:cloud_firestore/cloud_firestore.dart';

class BannerConfigModel {
  const BannerConfigModel({
    this.enabled = true,
    this.pricingTiers = const {24: 300, 72: 750, 168: 1500, 720: 5000},
    this.maxActiveBanners = 10,
    this.bannerNotice = '',
    this.updatedAt,
  });

  final bool enabled;
  final Map<int, int> pricingTiers;
  final int maxActiveBanners;
  final String bannerNotice;
  final DateTime? updatedAt;

  factory BannerConfigModel.fromMap(Map<String, dynamic> data) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final rawTiers = data['pricingTiers'] ?? data['pricing_tiers'];
    final Map<int, int> tiers = {};
    if (rawTiers is Map) {
      rawTiers.forEach((k, v) {
        final hours = int.tryParse(k.toString());
        final price = (v as num?)?.toInt();
        if (hours != null && price != null) {
          tiers[hours] = price;
        }
      });
    }

    return BannerConfigModel(
      enabled: data['enabled'] ?? true,
      pricingTiers: tiers.isNotEmpty
          ? tiers
          : const {24: 300, 72: 750, 168: 1500, 720: 5000},
      maxActiveBanners: (data['maxActiveBanners'] ?? data['max_active_banners'] as num?)?.toInt() ?? 10,
      bannerNotice: (data['bannerNotice'] ?? data['banner_notice']) as String? ?? '',
      updatedAt: parseDate(data['updatedAt'] ?? data['updated_at']),
    );
  }

  factory BannerConfigModel.fromFirestore(DocumentSnapshot doc) {
    if (!doc.exists || doc.data() == null) {
      return const BannerConfigModel();
    }
    return BannerConfigModel.fromMap(doc.data() as Map<String, dynamic>);
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> rawTiers = {};
    pricingTiers.forEach((k, v) {
      rawTiers[k.toString()] = v;
    });

    return {
      'enabled': enabled,
      'pricingTiers': rawTiers,
      'maxActiveBanners': maxActiveBanners,
      'bannerNotice': bannerNotice,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
