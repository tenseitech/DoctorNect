import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/profile_completion_service.dart';
import 'package:medibond/core/config/ambulance_enabled.dart';
import 'package:medibond/core/config/ambulance_entry_points.dart';
import 'package:medibond/core/config/doctor_patient_cutover_flag.dart';
import 'package:medibond/core/data/shared_appointments_store.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/firebase/firestore_paths.dart';
import 'package:medibond/core/notifications/app_notification.dart';
import 'package:medibond/core/notifications/doctor_notification_trigger.dart';
import 'package:medibond/core/notifications/in_app_notification_service.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/core/session/doctor_session.dart';
import 'package:medibond/core/session/patient_session.dart';
import 'package:medibond/core/supabase/in_app_notification_supabase_repository.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/patient/appointments/models/patient_appointment_models.dart';

void main() {
  group('SharedAppointmentsStore (Supabase path + optional Firestore test merge)', () {
    tearDown(() {
      SharedAppointmentsStore.instance.clearForSignOut();
      SharedAppointmentsStore.debugPatientSupabaseRefresh = null;
      SharedAppointmentsStore.debugPatientFirestoreRefresh = null;
      SharedAppointmentsStore.instance.clearForSignOut();
      SupabaseBootstrap.isReady = false;
    });

    test('merge uses Supabase rows; Firestore only via debugPatientFirestoreRefresh', () async {
      SupabaseBootstrap.isReady = true;
      SharedAppointmentsStore.debugPatientSupabaseRefresh = (_) async {
        return [
          DoctorNectAppointmentRecord(
            id: 'a1',
            appointmentId: 'ap1',
            doctorId: 'd1',
            doctorName: 'Dr A',
            specialization: 'GP',
            patientName: 'Pat',
            patientAge: 30,
            patientGender: 'M',
            dateTime: DateTime.utc(2026, 1, 1),
            slotLabel: '10:00',
            tokenNumber: 1,
            visitType: AppointmentType.newVisit,
            patientStatus: PatientBookingStatus.confirmed,
            doctorStatus: AppointmentStatus.confirmed,
          ),
        ];
      };
      SharedAppointmentsStore.debugPatientFirestoreRefresh = (_) async {
        return [
          DoctorNectAppointmentRecord(
            id: 'a2',
            appointmentId: 'ap2',
            doctorId: 'd1',
            doctorName: 'Dr A',
            specialization: 'GP',
            patientName: 'Other',
            patientAge: 20,
            patientGender: 'F',
            dateTime: DateTime.utc(2026, 1, 2),
            slotLabel: '11:00',
            tokenNumber: 2,
            visitType: AppointmentType.newVisit,
            patientStatus: PatientBookingStatus.confirmed,
            doctorStatus: AppointmentStatus.confirmed,
          ),
        ];
      };

      await SharedAppointmentsStore.instance.refreshForPatient('p1');
      expect(SharedAppointmentsStore.instance.records.length, 2);
      expect(
        SharedAppointmentsStore.instance.records.map((r) => r.id).toSet(),
        {'a1', 'a2'},
      );
    });

    test('Supabase failure sets lastError and throws', () async {
      SupabaseBootstrap.isReady = true;
      SharedAppointmentsStore.debugPatientSupabaseRefresh = (_) async {
        throw Exception('network');
      };
      Object? caught;
      try {
        await SharedAppointmentsStore.instance.refreshForPatient('p1');
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(SharedAppointmentsStore.instance.lastError, isNotNull);
    });
  });

  group('InAppNotificationService (Supabase mark-read surface)', () {
    tearDown(() {
      InAppNotificationSupabaseRepository.instance.clearClientForTesting();
      InAppNotificationSupabaseRepository.resetMarkReadOverrideForTesting();
      InAppNotificationService.instance.clearAllNotifications();
      DoctorSession.loggedInDoctorId = '';
      PatientSession.loggedInPatientId = '';
    });

    test('markDoctorRead sets lastRemoteError when Supabase markRead fails', () async {
      DoctorSession.loggedInDoctorId = 'doc_x';
      InAppNotificationService.instance.mergeDoctorRemoteNotifications([
        AppNotification(
          id: 'n1',
          title: 'Test',
          body: 'Body',
          createdAt: DateTime.now(),
          type: AppNotificationType.system,
          doctorTrigger: DoctorNotificationTrigger.newAppointmentBooked,
        ),
      ]);

      InAppNotificationSupabaseRepository.debugMarkReadOverride =
          (String id) async {
        throw Exception('supabase down');
      };

      await expectLater(
        InAppNotificationService.instance.markDoctorRead('n1'),
        throwsException,
      );
      expect(InAppNotificationService.instance.lastRemoteError, isNotNull);
    });
  });

  group('ProfileCompletionService (Firestore only via debugFirestoreOverride)', () {
    late FakeFirebaseFirestore fakeFs;

    setUp(() {
      fakeFs = FakeFirebaseFirestore();
      ProfileCompletionService.debugFirestoreOverride = () => fakeFs;
      DoctorPatientCutoverFlag.debugOverride = false;
      SupabaseBootstrap.isReady = false;
      FirebaseBootstrap.isReady = true;
      ProfileCompletionService.instance.reset();
    });

    tearDown(() {
      ProfileCompletionService.debugFirestoreOverride = null;
      DoctorPatientCutoverFlag.resetForTesting();
      FirebaseBootstrap.isReady = false;
    });

    test('markComplete uses injected Firestore', () async {
      await fakeFs
          .collection(FirestorePaths.users)
          .doc('u1')
          .set({'profileCompleted': false});

      await ProfileCompletionService.instance.markComplete(
        role: UserType.doctor,
        uid: 'u1',
        profileId: 'doc1',
      );

      final snap =
          await fakeFs.collection(FirestorePaths.users).doc('u1').get();
      expect(snap.data()?['profileCompleted'], true);
    });
  });

  group('AmbulanceEnabled / tab mapping', () {
    tearDown(() {
      AmbulanceEnabled.resetForTesting();
    });

    test('logical tab 4 maps to physical 3 when Ambulance is off', () {
      AmbulanceEnabled.debugOverride = false;
      expect(
        AmbulanceEntryPoints.mapLogicalPatientTabToPhysical(
          4,
          showUnavailableToast: false,
        ),
        3,
      );
    });

    test('logical Ambulance tab is blocked when Ambulance is off', () {
      AmbulanceEnabled.debugOverride = false;
      expect(
        AmbulanceEntryPoints.mapLogicalPatientTabToPhysical(
          3,
          showUnavailableToast: false,
        ),
        isNull,
      );
    });
  });
}
