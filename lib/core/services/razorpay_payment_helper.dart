import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

class RazorpayPaymentResult {
  const RazorpayPaymentResult({
    required this.success,
    this.orderId,
    this.paymentId,
    this.signature,
    this.errorMessage,
  });

  final bool success;
  final String? orderId;
  final String? paymentId;
  final String? signature;
  final String? errorMessage;
}

class RazorpayPaymentHelper {
  static RazorpayPaymentHelper? _instance;
  static RazorpayPaymentHelper get instance =>
      _instance ??= RazorpayPaymentHelper._();

  RazorpayPaymentHelper._() {
    _initRazorpay();
  }

  late final Razorpay _razorpay;
  Completer<RazorpayPaymentResult>? _completer;

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(
        RazorpayPaymentResult(
          success: true,
          orderId: response.orderId,
          paymentId: response.paymentId,
          signature: response.signature,
        ),
      );
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(
        RazorpayPaymentResult(
          success: false,
          errorMessage: response.message ??
              'Payment failed or cancelled (code: ${response.code})',
        ),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (kDebugMode)
      debugPrint(
          '[RazorpayPaymentHelper] External wallet selected: ${response.walletName}');
  }

  /// Opens Razorpay Checkout modal with order parameters and returns result.
  Future<RazorpayPaymentResult> openCheckout({
    required String keyId,
    required String orderId,
    required num amountINR,
    required String title,
    required String description,
    required String prefillEmail,
    required String prefillContact,
  }) async {
    _completer = Completer<RazorpayPaymentResult>();

    final options = {
      'key': keyId,
      'amount': (amountINR * 100).toInt(),
      'name': title,
      'description': description,
      'order_id': orderId,
      'prefill': {
        'contact': prefillContact,
        'email': prefillEmail,
      },
      'theme': {
        'color': '#0F766E',
      },
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      if (kDebugMode)
        debugPrint('[RazorpayPaymentHelper] Error launching Checkout: $e');
      return RazorpayPaymentResult(
        success: false,
        errorMessage: 'Could not open Razorpay Checkout: $e',
      );
    }

    return _completer!.future;
  }

  void dispose() {
    _razorpay.clear();
  }
}
