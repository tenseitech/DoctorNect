import '../util/map_date_time.dart';

enum PromotedAdProviderType { doctor, lab, pharmacy, ambulance }

enum PromotedAdPaymentStatus { pending, verified, failed }

enum PromotedAdStatus { draft, pendingPayment, active, expired, rejected }

class PromotedAdModel {
  const PromotedAdModel({
    required this.adId,
    required this.providerType,
    required this.providerId,
    required this.title,
    required this.description,
    required this.imageUrl,
    this.imageKey,
    this.imageStorage,
    required this.ctaLabel,
    required this.durationHours,
    required this.amountPaid,
    this.targetCity,
    this.razorpayOrderId,
    this.razorpayPaymentId,
    required this.paymentStatus,
    required this.status,
    this.startTime,
    this.endTime,
    this.createdAt,
  });

  final String adId;
  final String providerType;
  final String providerId;
  final String title;
  final String description;
  final String imageUrl;
  final String? imageKey;
  final String? imageStorage;
  final String ctaLabel;
  final int durationHours;
  final num amountPaid;
  final String? targetCity;
  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final String paymentStatus;
  final String status;
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? createdAt;

  bool get isActive =>
      status == 'active' && endTime != null && endTime!.isAfter(DateTime.now());

  String get ownerDashboardLabel => switch (status) {
        'active' => 'ACTIVE',
        'pending_payment' => 'PENDING PAYMENT',
        'pending_approval' => 'UNDER REVIEW',
        'expired' => 'EXPIRED',
        'rejected' => 'REJECTED',
        _ => 'DRAFT',
      };

  int get remainingMinutes {
    if (!isActive || endTime == null) return 0;
    final diff = endTime!.difference(DateTime.now()).inMinutes;
    return diff > 0 ? diff : 0;
  }

  String get remainingTimeString {
    final mins = remainingMinutes;
    if (mins <= 0) return 'Expired';
    final hrs = mins ~/ 60;
    final remMins = mins % 60;
    if (hrs >= 24) {
      final days = hrs ~/ 24;
      return '$days d ${hrs % 24} h remaining';
    }
    if (hrs > 0) {
      return '$hrs h $remMins m remaining';
    }
    return '$mins mins remaining';
  }

  factory PromotedAdModel.fromRow(Map<String, dynamic> row) {
    return PromotedAdModel(
      adId: (row['ad_id'] ?? row['adId'] ?? '').toString(),
      providerType: ((row['provider_type'] ?? row['providerType']) as String?)
              ?.toLowerCase() ??
          'doctor',
      providerId: (row['provider_id'] ?? row['providerId'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      description: (row['description'] ?? '').toString(),
      imageUrl: (row['image_url'] ?? row['imageUrl'] ?? '').toString(),
      imageKey: (row['image_s3_key'] ?? row['image_key'] ?? row['imageKey'])
          as String?,
      imageStorage: (row['image_storage_provider'] ??
          row['image_storage'] ??
          row['imageStorage'] ??
          's3') as String?,
      ctaLabel:
          (row['cta_label'] ?? row['ctaLabel'] ?? 'View Details').toString(),
      durationHours:
          ((row['duration_hours'] ?? row['durationHours']) as num?)?.toInt() ??
              24,
      amountPaid: ((row['amount_paid'] ?? row['amountPaid']) as num?) ?? 300,
      targetCity: (row['target_city'] ?? row['targetCity']) as String?,
      razorpayOrderId:
          (row['razorpay_order_id'] ?? row['razorpayOrderId']) as String?,
      razorpayPaymentId:
          (row['razorpay_payment_id'] ?? row['razorpayPaymentId']) as String?,
      paymentStatus:
          ((row['payment_status'] ?? row['paymentStatus']) as String?)
                  ?.toLowerCase() ??
              'pending',
      status: ((row['status']) as String?)?.toLowerCase() ?? 'draft',
      startTime: parseMapDateTime(row['start_time'] ?? row['startTime']),
      endTime: parseMapDateTime(row['end_time'] ?? row['endTime']),
      createdAt: parseMapDateTime(row['created_at'] ?? row['createdAt']),
    );
  }

  factory PromotedAdModel.fromMap(Map<String, dynamic> data, {String? id}) {
    return PromotedAdModel(
      adId: id ?? (data['adId'] as String? ?? ''),
      providerType:
          (data['providerType'] as String?)?.toLowerCase() ?? 'doctor',
      providerId: data['providerId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      imageKey: data['imageKey'] as String?,
      imageStorage: data['imageStorage'] as String?,
      ctaLabel: data['ctaLabel'] as String? ?? 'View Details',
      durationHours: (data['durationHours'] as num?)?.toInt() ?? 24,
      amountPaid: (data['amountPaid'] as num?) ?? 300,
      targetCity: data['targetCity'] as String?,
      razorpayOrderId: data['razorpayOrderId'] as String?,
      razorpayPaymentId: data['razorpayPaymentId'] as String?,
      paymentStatus:
          (data['paymentStatus'] as String?)?.toLowerCase() ?? 'pending',
      status: (data['status'] as String?)?.toLowerCase() ?? 'draft',
      startTime: parseMapDateTime(data['startTime']),
      endTime: parseMapDateTime(data['endTime']),
      createdAt: parseMapDateTime(data['createdAt']),
    );
  }
}
