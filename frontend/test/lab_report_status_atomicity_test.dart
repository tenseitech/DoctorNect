import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/firebase/lab_report_persist_verify.dart';
import 'package:medibond/core/supabase/repositories/supabase_lab_repository.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';

void main() {
  tearDown(SupabaseLabRepository.debugResetForTesting);

  group('SupabaseLabRepository report key + status ordering', () {
    test('booking: key via RPC only; rollback clear when RPC fails (not completed)', () async {
      SupabaseBootstrap.isReady = true;
      final sequence = <String>[];

      SupabaseLabRepository.debugPersistLabBookingReportKeyOverride =
          (id, key) async {
        sequence.add('persist:$key');
      };
      SupabaseLabRepository.debugClearLabBookingReportKeyOverride = (id) async {
        sequence.add('clear');
      };
      SupabaseLabRepository.debugLabBookingReportStateFetcher = (_) async {
        return (status: 'inAnalysis', key: 'lab_reports/p1/lb_1/r.pdf');
      };
      SupabaseLabRepository.debugUpdateLabBookingStatusOverride =
          ({required bookingId, required newStatus, notes}) async {
        sequence.add('rpc');
        return false;
      };

      final ok = await SupabaseLabRepository.instance.updateLabBookingStatus(
        bookingId: 'lb_1',
        newStatus: 'completed',
        reportStorageKey: 'lab_reports/p1/lb_1/r.pdf',
      );

      expect(ok, isFalse);
      expect(sequence, ['rpc', 'clear']);
    });

    test('booking: RPC throw but status completed — do not clear key', () async {
      SupabaseBootstrap.isReady = true;
      final sequence = <String>[];

      SupabaseLabRepository.debugPersistLabBookingReportKeyOverride =
          (_, key) async {
        sequence.add('persist:$key');
      };
      SupabaseLabRepository.debugClearLabBookingReportKeyOverride = (_) async {
        sequence.add('clear');
      };
      SupabaseLabRepository.debugLabBookingReportStateFetcher = (_) async {
        return (status: 'completed', key: 'lab_reports/p1/lb_1/r.pdf');
      };
      SupabaseLabRepository.debugUpdateLabBookingStatusOverride =
          ({required bookingId, required newStatus, notes}) async {
        sequence.add('rpc');
        throw StateError('timeout');
      };

      await expectLater(
        SupabaseLabRepository.instance.updateLabBookingStatus(
          bookingId: 'lb_1',
          newStatus: 'completed',
          reportStorageKey: 'lab_reports/p1/lb_1/r.pdf',
        ),
        throwsStateError,
      );

      expect(sequence, ['rpc']);
    });

    test('verifyLinkedLabBookingReportKeys requires completed status', () async {
      SupabaseLabRepository.debugLabBookingReportStateFetcher = (_) async {
        return (status: 'inAnalysis', key: 'lab_reports/p1/lb_1/r.pdf');
      };

      final r = await SupabaseLabRepository.instance.verifyLinkedLabBookingReportKeys(
        ['lb_1'],
        'lab_reports/p1/lb_1/r.pdf',
      );
      expect(r, LabReportKeyCheckResult.noRowsMatch);

      SupabaseLabRepository.debugLabBookingReportStateFetcher = (_) async {
        return (status: 'completed', key: 'lab_reports/p1/lb_1/r.pdf');
      };
      final ok = await SupabaseLabRepository.instance.verifyLinkedLabBookingReportKeys(
        ['lb_1'],
        'lab_reports/p1/lb_1/r.pdf',
      );
      expect(ok, LabReportKeyCheckResult.allRowsMatch);
    });

    test('order: key via RPC only; clear key when RPC throws', () async {
      SupabaseBootstrap.isReady = true;
      final sequence = <String>[];

      SupabaseLabRepository.debugPersistLabOrderReportKeyOverride =
          (id, key) async {
        sequence.add('persist:$key');
      };
      SupabaseLabRepository.debugClearLabOrderReportKeyOverride = (id) async {
        sequence.add('clear');
      };
      SupabaseLabRepository.debugLabOrderReportStateFetcher = (_) async {
        return (status: 'inProgress', key: 'lab_reports/p1/ord_1/r.pdf');
      };
      SupabaseLabRepository.debugUpdateLabOrderStatusOverride =
          ({required orderId, required newStatus, notes}) async {
        sequence.add('rpc');
        throw StateError('rpc failed');
      };

      await expectLater(
        SupabaseLabRepository.instance.updateLabOrderStatus(
          orderId: 'ord_1',
          newStatus: 'completed',
          reportStorageKey: 'lab_reports/p1/ord_1/r.pdf',
        ),
        throwsStateError,
      );

      expect(sequence, ['rpc', 'clear']);
    });
  });
}
