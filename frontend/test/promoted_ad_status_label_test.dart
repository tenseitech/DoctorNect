import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/models/promoted_ad_model.dart';

PromotedAdModel _ad(String status) {
  return PromotedAdModel(
    adId: 'ad_1',
    providerType: 'doctor',
    providerId: 'doc_1',
    title: 'Campaign',
    description: 'Desc',
    imageUrl: 'https://example.com/banner.jpg',
    ctaLabel: 'Book',
    durationHours: 24,
    amountPaid: 300,
    paymentStatus: 'verified',
    status: status,
  );
}

void main() {
  test('provider ads list labels pending_approval and rejected clearly', () {
    expect(_ad('pending_approval').ownerDashboardLabel, 'UNDER REVIEW');
    expect(_ad('rejected').ownerDashboardLabel, 'REJECTED');
    expect(_ad('active').ownerDashboardLabel, 'ACTIVE');
    expect(_ad('pending_payment').ownerDashboardLabel, 'PENDING PAYMENT');
    expect(_ad('draft').ownerDashboardLabel, 'DRAFT');
  });

  test('public carousel eligibility stays status == active', () {
    expect(_ad('active').status, 'active');
    expect(_ad('pending_approval').status, isNot('active'));
    expect(_ad('rejected').status, isNot('active'));
    expect(_ad('pending_approval').isActive, isFalse);
  });
}
