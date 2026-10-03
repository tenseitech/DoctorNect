import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/notifications/app_notification.dart';
import 'package:medibond/core/notifications/in_app_notification_service.dart';
import 'package:medibond/core/notifications/notifications_inbox_screen.dart';
import 'package:medibond/core/notifications/widgets/notification_bell_button.dart';
import 'package:medibond/core/session/doctor_session.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/ambulance/ambulance_booking_screen.dart';
import 'package:medibond/features/ambulance/models/ambulance_models.dart';
import 'package:medibond/features/doctor/home/widgets/doctor_home_sections.dart';
import 'package:medibond/features/doctor/home/widgets/patient_picker_sheet.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/doctor/pharmacy/doctor_connected_stores_screen.dart';
import 'package:medibond/features/doctor/profile/data/doctor_profile_store.dart';
import 'package:medibond/features/doctor/profile/models/doctor_profile_data.dart';
import 'package:medibond/features/pharmacy/data/medical_store_registry.dart';
import 'package:medibond/features/pharmacy/data/pharmacy_connection_store.dart';
import 'package:medibond/features/pharmacy/models/pharmacy_models.dart';
import 'package:medibond/features/auth/widgets/registration_address_section.dart';
import 'package:medibond/features/patient/home/widgets/patient_address_sheet.dart';
import 'package:medibond/features/patient/profile/data/patient_profile_mock.dart';
import 'package:medibond/features/patient/profile/edit_profile_screen.dart';
import 'package:medibond/features/patient/profile/models/patient_profile_models.dart';
import 'package:medibond/features/welcome/welcome_screen.dart';
import 'package:medibond/widgets/digital_health_card_sheet.dart';
import 'package:medibond/widgets/emergency_sos_sheet.dart';
import 'package:medibond/widgets/header_overflow_menu.dart';
import 'package:medibond/widgets/required_field_label.dart';
import 'package:medibond/widgets/role_card.dart';
import 'package:medibond/widgets/theme_toggle_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DoctorSession.setDoctor(id: 'doc-test-001', name: 'Aarav Sharma');
    DoctorProfileStore.instance.profile = DoctorProfileData(
      fullName: 'Aarav Sharma',
      specialization: 'Cardiology',
      verificationStatus: VerificationStatus.verified,
      rating: 4.9,
      reviewCount: 25,
      councilNumber: 'MAH123456',
      stateCouncil: 'Maharashtra',
    );
  });

  tearDown(() {
    DoctorSession.clear();
  });

  group('Doctor Header & Clinical Tools Relocation Tests', () {
    testWidgets(
      'DoctorHomeTopBar has 12px horizontal spacing between ThemeToggleButton and NotificationBellButton and no 3-dot HeaderOverflowMenu',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.doctorBlue),
            home: const Scaffold(
              body: DoctorHomeTopBar(
                displayName: 'Aarav Sharma',
                verificationStatus: VerificationStatus.verified,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final themeRect = tester.getRect(find.byType(ThemeToggleButton));
        final bellRect = tester.getRect(find.byType(NotificationBellButton));

        expect(bellRect.left - themeRect.right, 12.0);
        expect(find.byType(HeaderOverflowMenu), findsNothing);
      },
    );

    testWidgets(
      'Clinical tools section renders Doctor Pass and Emergency SOS tiles and opens their sheets on tap',
      (tester) async {
        tester.view.physicalSize = const Size(500, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.doctorBlue),
            home: Scaffold(
              body: Builder(
                builder: (context) => DoctorHomeServicesSection(
                  title: 'Clinical tools',
                  services: [
                    DoctorHomeServiceItem(
                      label: 'Doctor Pass',
                      shortLabel: 'Doctor Pass',
                      subtitle: 'Doctor credentials & QR',
                      icon: Icons.badge_rounded,
                      assetPath: 'assets/icons/common/digital_pass.png',
                      gradient: const [Color(0xFF0D9488), Color(0xFF0369A1)],
                      onTap: () => DigitalHealthCardSheet.show(
                        context,
                        userType: UserType.doctor,
                      ),
                    ),
                    DoctorHomeServiceItem(
                      label: 'Emergency SOS',
                      shortLabel: 'Emergency SOS',
                      subtitle: '24/7 emergency response',
                      icon: Icons.emergency_rounded,
                      gradient: const [Color(0xFFDC2626), Color(0xFFB91C1C)],
                      onTap: () => EmergencySosSheet.show(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Doctor Pass'), findsOneWidget);
        expect(find.text('Emergency SOS'), findsOneWidget);

        // Tap Doctor Pass tile and verify DigitalHealthCardSheet opens
        await tester.tap(find.text('Doctor Pass'));
        await tester.pumpAndSettle();
        expect(find.text('Digital Doctor Credentials Pass'), findsOneWidget);

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        // Tap Emergency SOS tile and verify EmergencySosSheet opens
        await tester.tap(find.text('Emergency SOS'));
        await tester.pumpAndSettle();
        expect(find.text('Emergency SOS Assistance'), findsOneWidget);
      },
    );

    test(
        'doctor_home_screen.dart _clinicalServices includes Doctor Pass and Emergency SOS entries and _networkServices renames Refer a Colleague',
        () {
      final source = File('lib/features/doctor/home/doctor_home_screen.dart')
          .readAsStringSync();
      expect(source, contains("label: 'Doctor Pass'"));
      expect(source, contains("label: 'Emergency SOS'"));
      expect(source, contains('DigitalHealthCardSheet.show'));
      expect(source, contains('EmergencySosSheet.show'));
      expect(source, contains("label: 'Refer a Colleague'"));
      expect(source, contains("shortLabel: 'Refer a Colleague'"));
      expect(source, contains("subtitle: 'Send a referral'"));
      expect(source, isNot(contains("label: 'Refer another Doctor'")));
    });

    testWidgets(
      'Order Lab Test and Reschedule Appointment bottom sheets open to the exact same height and leave header area visible above',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final uniquePatients = List.generate(
          4,
          (i) => Appointment(
            id: 'p-$i',
            tokenNumber: i + 1,
            patientName: 'Patient $i',
            age: 30 + i,
            gender: 'Male',
            appointmentDate: DateTime(2026, 9, 26),
            timeSlot: '',
            status: AppointmentStatus.confirmed,
            type: AppointmentType.newVisit,
          ),
        );

        final reschedulableAppointments = List.generate(
          12,
          (i) => Appointment(
            id: 'appt-$i',
            tokenNumber: i + 1,
            patientName: 'Patient ${i % 4}',
            age: 30 + (i % 4),
            gender: 'Male',
            appointmentDate: DateTime(2026, 9, 26 + i),
            timeSlot: '10:00 AM',
            status: AppointmentStatus.confirmed,
            type: AppointmentType.newVisit,
          ),
        );

        late BuildContext savedContext;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.doctorBlue),
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  savedContext = ctx;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        );

        // 1. Open Order Lab Test bottom sheet (4 unique patients)
        PatientPickerSheet.show(
          savedContext,
          title: 'Order Lab Test',
          subtitle: 'Search and pick a patient',
          appointments: uniquePatients,
        );
        await tester.pumpAndSettle();

        final labRect = tester.getRect(find.byType(PatientPickerSheet));
        expect(labRect.top, greaterThan(200));

        Navigator.pop(savedContext);
        await tester.pumpAndSettle();

        // 2. Open Reschedule Appointment bottom sheet (12 appointments for those 4 patients)
        PatientPickerSheet.show(
          savedContext,
          title: 'Reschedule Appointment',
          subtitle: 'Search and pick an appointment',
          appointments: reschedulableAppointments,
          showAppointmentDate: true,
          maxVisibleItems: uniquePatients.length,
        );
        await tester.pumpAndSettle();

        final rescheduleRect = tester.getRect(find.byType(PatientPickerSheet));
        expect(rescheduleRect.top, greaterThan(200));
        expect(rescheduleRect.height, equals(labRect.height));
        expect(rescheduleRect.top, equals(labRect.top));
      },
    );

    for (final role in [
      AmbulanceBookedByRole.doctor,
      AmbulanceBookedByRole.patient,
    ]) {
      testWidgets(
        'Emergency Ambulance screen (${role.name}) shows English description on selecting each chip and wraps chips cleanly on mobile',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(
                role == AmbulanceBookedByRole.doctor
                    ? AppColors.doctorBlue
                    : AppColors.patientTeal,
              ),
              home: AmbulanceBookingScreen(bookedByRole: role),
            ),
          );
          await tester.pumpAndSettle();

          // Verify default "All Types" English description is shown
          expect(
            find.text(
              'For the fastest match. The nearest available ambulance will be assigned.',
            ),
            findsOneWidget,
          );

          // Tap BLS chip
          await tester.tap(find.text('BLS'));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Basic care with trained EMTs: oxygen, CPR, bleeding control, splinting. For stable or non-critical patients.',
            ),
            findsOneWidget,
          );

          // Tap ALS chip
          await tester.tap(find.text('ALS'));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Advanced care with paramedics: cardiac monitor/ECG, defibrillator, IV medicines, airway management. For critical cases (heart attack, stroke, serious injury).',
            ),
            findsOneWidget,
          );

          // Tap ICU chip
          await tester.tap(find.text('ICU'));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Critical care team with ventilator and ICU equipment. For severe life support or hospital ICU transfers.',
            ),
            findsOneWidget,
          );

          // Tap Transport chip
          await tester.tap(find.text('Transport'));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Non-emergency travel: wheelchair/stretcher support, for routine checkups or hospital discharge. Not for emergency care.',
            ),
            findsOneWidget,
          );

          // Tap All Types chip again
          await tester.tap(find.text('All Types'));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'For the fastest match. The nearest available ambulance will be assigned.',
            ),
            findsOneWidget,
          );

          // Verify mobile chip wrapping: 2-3 chips per row (not all 4-5 crammed on one line)
          final chipLabels = ['All Types', 'BLS', 'ALS', 'ICU', 'Transport'];
          final rowTops = <double>{};
          final chipsPerRow = <double, int>{};
          for (final label in chipLabels) {
            final dy = tester.getTopLeft(find.text(label)).dy;
            rowTops.add(dy);
            chipsPerRow[dy] = (chipsPerRow[dy] ?? 0) + 1;
          }
          expect(rowTops.length, greaterThanOrEqualTo(2));
          for (final count in chipsPerRow.values) {
            expect(count, lessThanOrEqualTo(3));
          }
        },
      );
    }

    testWidgets(
      'DoctorHomeStatsStrip merges stats row and search bar into one unified container with no horizontal seam and zero mobile overflow',
      (tester) async {
        final statItems = [
          DoctorHomeStatItem(
            label: 'Today',
            value: '12',
            gradient: const [AppColors.doctorBlue, Color(0xFF0F4A82)],
            icon: Icons.calendar_today,
            onTap: () {},
          ),
          DoctorHomeStatItem(
            label: 'Pending',
            value: '4',
            gradient: const [Color(0xFFEA580C), Color(0xFFC2410C)],
            icon: Icons.hourglass_bottom,
            onTap: () {},
          ),
          DoctorHomeStatItem(
            label: 'Completed',
            value: '8',
            gradient: const [Color(0xFF16A34A), Color(0xFF15803D)],
            icon: Icons.check_circle_outline,
            onTap: () {},
          ),
          DoctorHomeStatItem(
            label: 'Refer',
            value: '3',
            gradient: const [Color(0xFF7C3AED), Color(0xFF6D28D9)],
            icon: Icons.share,
            onTap: () {},
          ),
        ];

        for (final viewport in [
          const Size(320, 640),
          const Size(360, 780),
          const Size(390, 844),
          const Size(1200, 900),
        ]) {
          tester.view.physicalSize = viewport;
          tester.view.devicePixelRatio = 1.0;

          var searchTapped = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(AppColors.doctorBlue),
              home: Scaffold(
                body: DoctorHomeStatsStrip(
                  items: statItems,
                  selectedDate: DateTime(2026, 9, 26),
                  onCalendarTap: () {},
                  onSearchTap: () => searchTapped = true,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Today'), findsOneWidget);
          expect(find.text('Pending'), findsOneWidget);
          expect(
            find.text(viewport.width < 600 ? 'Done' : 'Completed'),
            findsOneWidget,
          );
          expect(find.text('Refer'), findsOneWidget);
          expect(
            find.text('Search for patient, medical, lab and ambulance'),
            findsOneWidget,
          );

          await tester.tap(
            find.text('Search for patient, medical, lab and ambulance'),
          );
          await tester.pumpAndSettle();
          expect(searchTapped, isTrue);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }

        tester.view.resetPhysicalSize();
      },
    );

    testWidgets(
      'DoctorHomeStatsStrip search bar rotates placeholders every 2.5s with 400ms transition matching Patient HomeSearchBar',
      (tester) async {
        final statItems = [
          DoctorHomeStatItem(
            label: 'Today',
            value: '12',
            gradient: const [Color(0xFF0284C7), Color(0xFF0369A1)],
            icon: Icons.today,
            onTap: () {},
          ),
          DoctorHomeStatItem(
            label: 'Pending',
            value: '4',
            gradient: const [Color(0xFFD97706), Color(0xFFB45309)],
            icon: Icons.schedule,
            onTap: () {},
          ),
          DoctorHomeStatItem(
            label: 'Completed',
            value: '8',
            gradient: const [Color(0xFF16A34A), Color(0xFF15803D)],
            icon: Icons.check_circle_outline,
            onTap: () {},
          ),
          DoctorHomeStatItem(
            label: 'Refer',
            value: '3',
            gradient: const [Color(0xFF7C3AED), Color(0xFF6D28D9)],
            icon: Icons.share,
            onTap: () {},
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.doctorBlue),
            home: Scaffold(
              body: DoctorHomeStatsStrip(
                items: statItems,
                selectedDate: DateTime(2026, 9, 26),
                onCalendarTap: () {},
                onSearchTap: () {},
              ),
            ),
          ),
        );

        expect(
          find.text('Search for patient, medical, lab and ambulance'),
          findsOneWidget,
        );

        await tester.pump(const Duration(milliseconds: 2500));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Search for patient'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 2500));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Search for medical'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 2500));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Search for lab'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 2500));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Search for ambulance'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 2500));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.text('Search for patient, medical, lab and ambulance'),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });

  group('NotificationsInboxScreen header row mobile layout', () {
    testWidgets(
      'renders back button, Notifications title, unread chip, and Mark all read without overflow on 360px and 390px viewports',
      (tester) async {
        InAppNotificationService.instance.clearAllNotifications();
        final now = DateTime(2026, 9, 26, 14, 0);
        InAppNotificationService.instance.addDoctor(
          AppNotification(
            id: 'doc-notif-1',
            title: 'KYC verified — practice unlocked',
            body: 'Your medical council registration is verified.',
            createdAt: now,
            type: AppNotificationType.kyc,
          ),
        );
        InAppNotificationService.instance.addDoctor(
          AppNotification(
            id: 'doc-notif-2',
            title: 'New request: Kunal Verma',
            body: 'Video Consult requested for Sep 26, 2026 at 12:15 PM.',
            createdAt: now.subtract(const Duration(minutes: 5)),
            type: AppNotificationType.appointment,
          ),
        );
        InAppNotificationService.instance.addPatient(
          AppNotification(
            id: 'pat-notif-1',
            title: 'Appointment confirmed',
            body: 'Your appointment with Dr. Aarav Sharma is confirmed.',
            createdAt: now,
            type: AppNotificationType.appointment,
          ),
        );
        InAppNotificationService.instance.addPatient(
          AppNotification(
            id: 'pat-notif-2',
            title: 'Lab report ready',
            body: 'Complete Blood Count report is available to view.',
            createdAt: now.subtract(const Duration(minutes: 10)),
            type: AppNotificationType.labReport,
          ),
        );

        for (final audience in NotificationAudience.values) {
          for (final viewport in [const Size(360, 780), const Size(390, 844)]) {
            tester.view.physicalSize = viewport;
            tester.view.devicePixelRatio = 1.0;

            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light(AppColors.doctorBlue),
                home: NotificationsInboxScreen(audience: audience),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.text('Notifications'), findsOneWidget);
            expect(find.text('2 unread'), findsOneWidget);
            expect(find.text('Mark all read'), findsOneWidget);

            final unreadRect = tester.getRect(find.text('2 unread'));
            final markAllRect = tester.getRect(find.text('Mark all read'));
            expect(unreadRect.right, lessThanOrEqualTo(markAllRect.left));
            expect(markAllRect.right, lessThanOrEqualTo(viewport.width));
          }
        }

        InAppNotificationService.instance.clearAllNotifications();
        tester.view.resetPhysicalSize();
      },
    );
  });

  group('WelcomeScreen registration role selection', () {
    testWidgets(
      'renders exactly 5 roles (Doctor, Patient, Pharmacy, Lab, Ambulance) and does not render Super Admin',
      (tester) async {
        tester.view.physicalSize = const Size(390, 960);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.doctorBlue),
            home: const WelcomeScreen(
              verifiedMobile: '9876543210',
              verifiedOtp: '123456',
              isNewUser: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(RoleCard), findsNWidgets(5));
        expect(find.text('Doctor'), findsOneWidget);
        expect(find.text('Patient'), findsOneWidget);
        expect(find.text('Pharmacy'), findsOneWidget);
        expect(find.text('Lab'), findsOneWidget);
        expect(find.text('Ambulance'), findsOneWidget);
        expect(find.text('Admin / Super Admin'), findsNothing);
        expect(find.text('Super Admin'), findsNothing);

        tester.view.resetPhysicalSize();
      },
    );
  });

  group('DoctorConnectedStoresScreen city auto-discovery and UI', () {
    testWidgets(
      'removes Add Medical Store button, pins Connected stores on top, and lists remaining city stores alphabetically with Connect button',
      (tester) async {
        await MedicalStoreRegistry.refreshFromFirestore();
        PharmacyConnectionStore.instance.clear();

        DoctorProfileStore.instance.profile = DoctorProfileData(
          fullName: 'Aarav Sharma',
          specialization: 'Cardiology',
          verificationStatus: VerificationStatus.verified,
          rating: 4.9,
          reviewCount: 25,
          city: 'Mumbai',
          addressLine1: 'Andheri West, Mumbai',
        );

        final connectedStoreId = MedicalStoreRegistry.register(
          storeName: 'CityCare Chemist',
          ownerName: 'Ramesh Gupta',
          address: 'Bandra West, Mumbai',
          drugLicenseNumber: 'DL-MUM-001',
          phone: '9876500001',
          email: 'citycare@example.com',
        );
        MedicalStoreRegistry.register(
          storeName: 'Zenith Pharmacy',
          ownerName: 'Sunil Mehta',
          address: 'Dadar East, Mumbai',
          drugLicenseNumber: 'DL-MUM-002',
          phone: '9876500002',
          email: 'zenith@example.com',
        );
        MedicalStoreRegistry.register(
          storeName: 'Alpha Medico',
          ownerName: 'Priya Shah',
          address: 'Juhu Tara Road, Mumbai',
          drugLicenseNumber: 'DL-MUM-003',
          phone: '9876500003',
          email: 'alpha@example.com',
        );
        MedicalStoreRegistry.register(
          storeName: 'Delhi MedPlus',
          ownerName: 'Vikram Singh',
          address: 'Connaught Place, Delhi',
          drugLicenseNumber: 'DL-DEL-004',
          phone: '9876500004',
          email: 'delhi@example.com',
        );

        PharmacyConnectionStore.instance.mergeFirestoreConnections([
          PharmacyConnection(
            id: 'conn-1',
            doctorId: 'doc-test-001',
            doctorName: 'Aarav Sharma',
            medicalStoreId: connectedStoreId,
            storeName: 'CityCare Chemist',
            status: ConnectionStatus.active,
            requestedBy: ConnectionRequester.doctor,
            requestedAt: DateTime(2026, 9, 25),
          ),
        ]);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.doctorBlue),
            home: const Scaffold(
              body: DoctorConnectedStoresScreen(showAppBar: false),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. "+ Add Medical Store" button is removed, "Invite" remains
        expect(find.textContaining('Add Medical Store'), findsNothing);
        expect(find.text('Invite'), findsOneWidget);

        // 2. Connected section pinned on top with existing store card details
        expect(find.text('Connected'), findsOneWidget);
        expect(find.text('CityCare Chemist'), findsOneWidget);
        expect(find.text('0 prescriptions'), findsOneWidget);
        expect(find.text('View Patients'), findsOneWidget);

        // 3. Discovery section shows remaining Mumbai stores alphabetically and excludes Delhi store
        expect(find.text('All Medical Stores in Mumbai'), findsOneWidget);
        expect(find.text('Alpha Medico'), findsOneWidget);
        expect(find.text('Zenith Pharmacy'), findsOneWidget);
        expect(find.text('Delhi MedPlus'), findsNothing);
        expect(find.text('Connect'), findsNWidgets(2));

        final connectedY = tester.getTopLeft(find.text('CityCare Chemist')).dy;
        final alphaY = tester.getTopLeft(find.text('Alpha Medico')).dy;
        final zenithY = tester.getTopLeft(find.text('Zenith Pharmacy')).dy;
        expect(connectedY, lessThan(alphaY));
        expect(alphaY, lessThan(zenithY));

        await MedicalStoreRegistry.refreshFromFirestore();
        PharmacyConnectionStore.instance.clear();
      },
    );

    testWidgets(
      'shows empty-state message under discovery section when no other medical stores exist in doctor city',
      (tester) async {
        await MedicalStoreRegistry.refreshFromFirestore();
        PharmacyConnectionStore.instance.clear();

        DoctorProfileStore.instance.profile = DoctorProfileData(
          fullName: 'Aarav Sharma',
          specialization: 'Cardiology',
          verificationStatus: VerificationStatus.verified,
          rating: 4.9,
          reviewCount: 25,
          city: 'Pune',
          addressLine1: 'Koregaon Park, Pune',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.doctorBlue),
            home: const Scaffold(
              body: DoctorConnectedStoresScreen(showAppBar: false),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('All Medical Stores in Pune'), findsOneWidget);
        expect(
          find.text('No other medical stores found in Pune'),
          findsOneWidget,
        );
      },
    );
  });

  group(
      'Patient location validation (Pincode & Address optional, City/State/Country mandatory)',
      () {
    testWidgets(
      'RegistrationAddressSection in Patient mode makes Pincode and Address Line 1 optional (no asterisk) while requiring Country, State, and City',
      (tester) async {
        final formKey = GlobalKey<FormState>();
        final address1Ctrl = TextEditingController();
        final address2Ctrl = TextEditingController();
        final pinCodeCtrl = TextEditingController();
        String? country = 'India';
        String? state;
        String? city;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.patientTeal),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: RegistrationAddressSection(
                        initialCountry: country,
                        initialState: state,
                        initialCity: city,
                        onCountryChanged: (v) => setState(() => country = v),
                        onStateChanged: (v) => setState(() => state = v),
                        onCityChanged: (v) => setState(() => city = v),
                        address1Controller: address1Ctrl,
                        address2Controller: address2Ctrl,
                        pinCodeController: pinCodeCtrl,
                        accentColor: AppColors.patientTeal,
                        pinCodeRequired: false,
                        addressLine1Required: false,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // RequiredFieldLabel should only exist on Country, State, and City (3 fields), NOT on Pincode or Address Line 1
        final requiredLabels = tester
            .widgetList<RequiredFieldLabel>(find.byType(RequiredFieldLabel))
            .map((w) => w.text)
            .toList();
        expect(requiredLabels, containsAll(['Country', 'State', 'City']));
        expect(requiredLabels, isNot(contains('Pincode')));
        expect(requiredLabels, isNot(contains('Address Line 1')));

        // When State and City are empty, validation blocks submission
        expect(formKey.currentState!.validate(), isFalse);
        await tester.pump();
        expect(find.text('Please select State'), findsOneWidget);
        expect(find.text('Please select City'), findsOneWidget);
        expect(find.text('PIN / postal code is required'), findsNothing);
        expect(find.text('Enter address line 1'), findsNothing);

        // When Country, State, and City are provided and Pincode + Address are left blank, validation succeeds
        state = 'Maharashtra';
        city = 'Mumbai';
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.patientTeal),
            home: Scaffold(
              body: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: RegistrationAddressSection(
                    initialCountry: country,
                    initialState: state,
                    initialCity: city,
                    onCountryChanged: (_) {},
                    onStateChanged: (_) {},
                    onCityChanged: (_) {},
                    address1Controller: address1Ctrl,
                    address2Controller: address2Ctrl,
                    pinCodeController: pinCodeCtrl,
                    accentColor: AppColors.patientTeal,
                    pinCodeRequired: false,
                    addressLine1Required: false,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(formKey.currentState!.validate(), isTrue);

        address1Ctrl.dispose();
        address2Ctrl.dispose();
        pinCodeCtrl.dispose();
      },
    );

    testWidgets(
      'RegistrationAddressSection default mode (Pharmacy/Lab/Ambulance) still requires Pincode and Address Line 1',
      (tester) async {
        final formKey = GlobalKey<FormState>();
        final address1Ctrl = TextEditingController();
        final address2Ctrl = TextEditingController();
        final pinCodeCtrl = TextEditingController();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.pharmacyGreen),
            home: Scaffold(
              body: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: RegistrationAddressSection(
                    initialCountry: 'India',
                    initialState: 'Maharashtra',
                    initialCity: 'Mumbai',
                    onCountryChanged: (_) {},
                    onStateChanged: (_) {},
                    onCityChanged: (_) {},
                    address1Controller: address1Ctrl,
                    address2Controller: address2Ctrl,
                    pinCodeController: pinCodeCtrl,
                    accentColor: AppColors.pharmacyGreen,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(formKey.currentState!.validate(), isFalse);
        await tester.pump();
        expect(find.text('PIN / postal code is required'), findsOneWidget);
        expect(find.text('Enter address line 1'), findsOneWidget);

        address1Ctrl.dispose();
        address2Ctrl.dispose();
        pinCodeCtrl.dispose();
      },
    );

    testWidgets(
      'EditProfileScreen and PatientAddressSheet allow saving with blank Pincode and Address when Country, State, and City are filled',
      (tester) async {
        PatientProfileMock.reset();
        PatientProfileMock.profile
          ..name = 'Riya Verma'
          ..age = 29
          ..gender = 'Female'
          ..bloodGroup = 'O+'
          ..mobile = '+91 9876543210'
          ..email = 'riya@example.com';
        PatientProfileMock.profileAddress = const PatientAddress(
          country: 'India',
          state: 'Maharashtra',
          city: 'Mumbai',
          addressLine1: '',
          addressLine2: '',
          pincode: '',
        );

        // Profile completion is 100% even when addressLine1 and pincode are empty
        expect(PatientProfileMock.profileCompletionPercentage, 100);

        var savedCalled = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.patientTeal),
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => EditProfileScreen(
                              profile: PatientProfileMock.profile,
                              onSaved: () => savedCalled = true,
                            ),
                          ),
                        );
                      },
                      child: const Text('Open Edit Profile'),
                    ),
                    ElevatedButton(
                      onPressed: () => PatientAddressSheet.show(context),
                      child: const Text('Open Address Sheet'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Edit Profile'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();
        expect(savedCalled, isTrue);
        expect(PatientProfileMock.profileAddress.city, 'Mumbai');
        expect(PatientProfileMock.profileAddress.state, 'Maharashtra');
        expect(PatientProfileMock.profileAddress.country, 'India');
        expect(PatientProfileMock.profileAddress.pincode, isEmpty);
        expect(PatientProfileMock.profileAddress.addressLine1, isEmpty);

        // Also verify PatientAddressSheet submits cleanly with empty Pincode & Address
        await tester.tap(find.text('Open Address Sheet'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save location'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
