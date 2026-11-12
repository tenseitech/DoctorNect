import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/constants/app_constants.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/doctor/profile/sections/personal_info_section.dart';
import 'package:medibond/features/patient/booking/widgets/add_family_member_sheet.dart';
import 'package:medibond/features/profile/profile_completion_modal.dart';
import 'package:medibond/widgets/qualification_selector.dart';
import 'package:medibond/widgets/searchable_dropdown_form_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Selection Fallback Lists Integrity', () {
    test('AppConstants fallback lists are populated and contain Other', () {
      expect(AppConstants.doctorQualifications, isNotEmpty);
      expect(AppConstants.doctorQualifications, contains('Other'));
      expect(AppConstants.doctorQualifications, contains('MBBS'));

      expect(AppConstants.pharmacyQualifications, isNotEmpty);
      expect(AppConstants.pharmacyQualifications, contains('Other'));
      expect(AppConstants.pharmacyQualifications, contains('B.Pharm'));

      expect(AppConstants.labQualifications, isNotEmpty);
      expect(AppConstants.labQualifications, contains('Other'));
      expect(AppConstants.labQualifications, contains('DMLT'));

      expect(AppConstants.ambulanceQualifications, isNotEmpty);
      expect(AppConstants.ambulanceQualifications, contains('Other'));
      expect(AppConstants.ambulanceQualifications, contains('EMT-Basic'));

      expect(AppConstants.commonDoctorSpecializations, isNotEmpty);
      expect(AppConstants.commonDoctorSpecializations, contains('Other'));
      expect(AppConstants.commonDoctorSpecializations,
          contains('General Physician'));
    });
  });

  group('QualificationSelector Widget Tests', () {
    testWidgets('shows all options immediately on tap and selects',
        (tester) async {
      String? selectedVal;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QualificationSelector(
              items: const ['MBBS', 'MD', 'Other'],
              onChanged: (val) => selectedVal = val,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap to open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // Options should be visible immediately
      expect(find.text('MBBS'), findsWidgets);
      expect(find.text('MD'), findsWidgets);
      expect(find.text('Other'), findsWidgets);

      // Select MBBS
      await tester.tap(find.text('MBBS').last);
      await tester.pumpAndSettle();

      expect(selectedVal, 'MBBS');
    });

    testWidgets('selecting Other reveals free-text input field',
        (tester) async {
      String? selectedVal;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QualificationSelector(
              items: const ['MBBS', 'MD', 'Other'],
              onChanged: (val) => selectedVal = val,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap to open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // Tap Other
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();

      // Free-text field should now be visible
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Enter qualification *'), findsOneWidget);

      // Enter custom qualification
      await tester.enterText(
          find.byType(TextFormField), 'Fellowship in Cardiology');
      await tester.pumpAndSettle();

      expect(selectedVal, 'Fellowship in Cardiology');
    });

    testWidgets(
        'supports custom role-specific qualification items (e.g. Pharmacy)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QualificationSelector(
              items: AppConstants.pharmacyQualifications,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('B.Pharm'), findsWidgets);
      expect(find.text('D.Pharm'), findsWidgets);
      expect(find.text('Pharm.D'), findsWidgets);
    });
  });

  group('SearchableDropdownFormField Widget Tests', () {
    testWidgets(
        'opens modal sheet on tap, shows all items and filters on search',
        (tester) async {
      String? selectedVal;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchableDropdownFormField(
              title: 'Specialization',
              value: null,
              items: AppConstants.commonDoctorSpecializations,
              onChanged: (val) => selectedVal = val,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select Specialization'), findsOneWidget);

      // Tap to open bottom sheet
      await tester.tap(find.text('Select Specialization'));
      await tester.pumpAndSettle();

      // Header and search field should be visible
      expect(find.text('Select Specialization'), findsWidgets);
      expect(find.text('Cardiologist'), findsWidgets);
      expect(find.text('Dermatologist'), findsWidgets);

      // Filter by typing
      await tester.enterText(find.byType(TextField), 'Neuro');
      await tester.pumpAndSettle();

      expect(find.text('Neurologist'), findsWidgets);
      expect(find.text('Dermatologist'), findsNothing);

      // Select Neurologist
      await tester.tap(find.text('Neurologist'));
      await tester.pumpAndSettle();

      expect(selectedVal, 'Neurologist');
    });
  });

  group('AddFamilyMemberSheet Relation Selection Tests', () {
    testWidgets(
        'relation dropdown displays options immediately on tap and selects',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const Scaffold(
            body: AddFamilyMemberSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open relation dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // Verify immediate options without typing
      expect(find.text('Father'), findsWidgets);
      expect(find.text('Mother'), findsWidgets);
      expect(find.text('Spouse'), findsWidgets);
      expect(find.text('Son'), findsWidgets);

      // Select Father
      await tester.tap(find.text('Father').last);
      await tester.pumpAndSettle();

      expect(find.text('Father'), findsOneWidget);
    });
  });

  group('ProfileCompletionModal Doctor & Patient Selection Tests', () {
    testWidgets(
        'Doctor profile completion renders Specialization, Qualification, and Experience pickers',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.doctorBlue),
          home: const Scaffold(
            body: ProfileCompletionModal(
              role: UserType.doctor,
              isEditing: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Specialization field
      expect(find.text('Specialization *'), findsOneWidget);
      // Qualification selector
      expect(find.text('Highest Qualification *'), findsOneWidget);
      // Experience dropdown
      expect(find.text('Years of Experience'), findsOneWidget);
    });

    testWidgets(
        'Patient profile completion renders Gender and Blood Group dropdowns with Other',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const Scaffold(
            body: ProfileCompletionModal(
              role: UserType.patient,
              isEditing: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Gender dropdown
      expect(find.text('Gender'), findsOneWidget);
      // Blood Group dropdown
      expect(find.text('Blood Group'), findsOneWidget);
    });
  });

  group('Doctor PersonalInfoSection Gender Dropdown', () {
    testWidgets('gender dropdown is interactive and selectable',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.doctorBlue),
          home: const Scaffold(
            body: PersonalInfoSection(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gender'), findsOneWidget);
      final genderDropdown = find.byType(DropdownButtonFormField<String>);
      expect(genderDropdown, findsOneWidget);
    });
  });
}
