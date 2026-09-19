import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/invite/doctor_invite_service.dart';
import 'package:medibond/core/invite/ambulance_invite_service.dart';
import 'package:medibond/core/invite/invite_deep_link_resolver.dart';
import 'package:medibond/core/invite/pending_doctor_invite_store.dart';
import 'package:medibond/core/invite/pending_lab_invite_store.dart';
import 'package:medibond/core/invite/pending_pharmacy_invite_store.dart';
import 'package:medibond/core/invite/pharmacy_doctor_invite_service.dart';
import 'package:medibond/features/auth/unified_mobile_auth_screen.dart';

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

  group('invite deep link unified auth routing', () {
    void expectUnifiedAuth(UserType role, Widget? screen) {
      expect(screen, isA<UnifiedMobileAuthScreen>());
      expect((screen! as UnifiedMobileAuthScreen).role, role);
    }

    test('patient join link opens patient unified auth', () {
      PendingDoctorInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/join?doctor=d1784185736978'),
      );
      expectUnifiedAuth(
        UserType.patient,
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });

    test('pharmacy join link opens pharmacy unified auth', () {
      PendingDoctorInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/join?doctor=d1784185736978&role=pharmacy'),
      );
      expectUnifiedAuth(
        UserType.medicalStore,
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });

    test('lab join link opens lab unified auth', () {
      PendingDoctorInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/join?doctor=d1784185736978&role=lab'),
      );
      expectUnifiedAuth(
        UserType.lab,
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });

    test('doctor join link opens doctor unified auth', () {
      PendingDoctorInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/join?doctor=d1784185736978&role=doctor'),
      );
      expectUnifiedAuth(
        UserType.doctor,
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });

    test('ambulance join link opens ambulance unified auth', () {
      PendingDoctorInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/join?doctor=d1784185736978&role=ambulance'),
      );
      expectUnifiedAuth(
        UserType.ambulance,
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });

    test('pharmacy doctor download link opens doctor unified auth', () {
      PendingPharmacyInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/download?store=store-1&role=doctor'),
      );
      expectUnifiedAuth(
        UserType.doctor,
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });

    test('lab doctor download link opens doctor unified auth', () {
      PendingLabInviteStore.captureFromUri(
        Uri.parse('https://doctornect.com/download?lab=lab-1&role=doctor'),
      );
      expectUnifiedAuth(
        UserType.doctor,
        InviteDeepLinkResolver.loginScreenFromPendingInvite(),
      );
    });
  });
}
