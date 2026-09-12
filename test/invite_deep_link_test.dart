import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/invite/doctor_invite_service.dart';
import 'package:medibond/core/invite/ambulance_invite_service.dart';
import 'package:medibond/core/invite/invite_deep_link_resolver.dart';
import 'package:medibond/core/invite/pending_doctor_invite_store.dart';
import 'package:medibond/core/invite/pending_lab_invite_store.dart';
import 'package:medibond/core/invite/pending_pharmacy_invite_store.dart';
import 'package:medibond/core/invite/pharmacy_doctor_invite_service.dart';
import 'package:medibond/features/auth/doctor_login_screen.dart';
import 'package:medibond/features/auth/lab_login_screen.dart';
import 'package:medibond/features/auth/medical_store_login_screen.dart';
import 'package:medibond/features/auth/patient_login_screen.dart';
import 'package:medibond/features/ambulance/ambulance_login_screen.dart';

void main() {
  tearDown(() {
    PendingDoctorInviteStore.clear();
    PendingPharmacyInviteStore.clear();
    PendingLabInviteStore.clear();
  });

  group('invite link URLs use doctornect.com', () {
    test('doctor network invite links', () {
      expect(
        DoctorInviteService.buildNetworkInviteLink(
          doctorId: 'd1784185736978',
          userType: InviteNetworkUserType.patient,
        ),
        'https://doctornect.com/join?doctor=d1784185736978',
      );
      expect(
        DoctorInviteService.buildNetworkInviteLink(
          doctorId: 'd1784185736978',
          userType: InviteNetworkUserType.medicalStore,
        ),
        'https://doctornect.com/join?doctor=d1784185736978&role=pharmacy',
      );
      expect(
        DoctorInviteService.buildNetworkInviteLink(
          doctorId: 'd1784185736978',
          userType: InviteNetworkUserType.lab,
        ),
        'https://doctornect.com/join?doctor=d1784185736978&role=lab',
      );
      expect(
        DoctorInviteService.buildNetworkInviteLink(
          doctorId: 'd1784185736978',
          userType: InviteNetworkUserType.doctor,
        ),
        'https://doctornect.com/join?doctor=d1784185736978&role=doctor',
      );
      expect(
        DoctorInviteService.buildNetworkInviteLink(
          doctorId: 'd1784185736978',
          userType: InviteNetworkUserType.ambulance,
        ),
        'https://doctornect.com/join?doctor=d1784185736978&role=ambulance',
      );
    });

    test('pharmacy and ambulance invite links', () {
      expect(
        PharmacyDoctorInviteService.buildInviteLink('store-1'),
        'https://doctornect.com/download?store=store-1&role=doctor',
      );
      expect(
        AmbulanceInviteService.buildInviteLink(inviteId: 'inv-1', token: 'tok-1'),
        'https://doctornect.com/ambulance-setup?invite=inv-1&token=tok-1',
      );
    });
  });

  group('invite deep link login routing', () {
    void expectLoginScreen<T extends Widget>(Widget? screen) {
      expect(screen, isA<T>());
    }

    test('patient join link opens patient login', () {
      PendingDoctorInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/join?doctor=d1784185736978'),
      );
      expectLoginScreen<PatientLoginScreen>(
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });

    test('pharmacy join link opens medical store login', () {
      PendingDoctorInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/join?doctor=d1784185736978&role=pharmacy'),
      );
      expectLoginScreen<MedicalStoreLoginScreen>(
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });

    test('lab join link opens lab login', () {
      PendingDoctorInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/join?doctor=d1784185736978&role=lab'),
      );
      expectLoginScreen<LabLoginScreen>(
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });

    test('doctor join link opens doctor login', () {
      PendingDoctorInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/join?doctor=d1784185736978&role=doctor'),
      );
      expectLoginScreen<DoctorLoginScreen>(
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });

    test('ambulance join link opens ambulance login', () {
      PendingDoctorInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/join?doctor=d1784185736978&role=ambulance'),
      );
      expectLoginScreen<AmbulanceLoginScreen>(
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });

    test('pharmacy doctor download link opens doctor login', () {
      PendingPharmacyInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/download?store=store-1&role=doctor'),
      );
      expectLoginScreen<DoctorLoginScreen>(
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });

    test('lab doctor download link opens doctor login', () {
      PendingLabInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/download?lab=lab-1&role=doctor'),
      );
      expectLoginScreen<DoctorLoginScreen>(
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });
  });
}
