import 'package:cloud_firestore/cloud_firestore.dart';

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
  final String providerType; // 'doctor', 'lab', 'pharmacy', 'ambulance'
  final String providerId;
  final String title;
  final String description;
  final String imageUrl;
  final String ctaLabel;
  final int durationHours;
  final num amountPaid;
  final String? targetCity;
  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final String paymentStatus; // 'pending', 'verified', 'failed'
  final String status; // 'draft', 'pending_payment', 'active', 'expired', 'rejected'
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? createdAt;

  bool get isActive => status == 'active' && endTime != null && endTime!.isAfter(DateTime.now());

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

  factory PromotedAdModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return PromotedAdModel(
      adId: doc.id,
      providerType: (data['providerType'] as String?)?.toLowerCase() ?? 'doctor',
      providerId: data['providerId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      ctaLabel: data['ctaLabel'] as String? ?? 'View Details',
      durationHours: (data['durationHours'] as num?)?.toInt() ?? 24,
      amountPaid: (data['amountPaid'] as num?) ?? 300,
      targetCity: data['targetCity'] as String?,
      razorpayOrderId: data['razorpayOrderId'] as String?,
      razorpayPaymentId: data['razorpayPaymentId'] as String?,
      paymentStatus: (data['paymentStatus'] as String?)?.toLowerCase() ?? 'pending',
      status: (data['status'] as String?)?.toLowerCase() ?? 'draft',
      startTime: parseDate(data['startTime']),
      endTime: parseDate(data['endTime']),
      createdAt: parseDate(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'providerType': providerType,
      'providerId': providerId,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'ctaLabel': ctaLabel,
      'durationHours': durationHours,
      'amountPaid': amountPaid,
      if (targetCity != null) 'targetCity': targetCity,
      if (razorpayOrderId != null) 'razorpayOrderId': razorpayOrderId,
      if (razorpayPaymentId != null) 'razorpayPaymentId': razorpayPaymentId,
      'paymentStatus': paymentStatus,
      'status': status,
      if (startTime != null) 'startTime': Timestamp.fromDate(startTime!),
      if (endTime != null) 'endTime': Timestamp.fromDate(endTime!),
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }
}
