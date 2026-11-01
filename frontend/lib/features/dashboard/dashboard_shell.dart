import 'package:flutter/material.dart';

import '../../core/enums/user_type.dart';
import '../../core/session/ambulance_session.dart';
import '../../core/session/doctor_session.dart';
import '../../core/theme/app_colors.dart';
import '../ambulance/data/ambulance_store.dart';
import '../ambulance/models/ambulance_models.dart';

import '../ambulance/ambulance_shell.dart' deferred as ambulance_module;
import '../doctor/verification/doctor_verification_gate.dart' deferred as doctor_module;
import '../patient/patient_shell.dart' deferred as patient_module;
import '../pharmacy/medical_store_shell.dart' deferred as pharmacy_module;
import '../lab/lab_shell.dart' deferred as lab_module;
import '../admin/super_admin_verification_screen.dart' deferred as admin_module;

class DashboardShell extends StatelessWidget {
  const DashboardShell({super.key, required this.userType});

  final UserType userType;

  @override
  Widget build(BuildContext context) {
    return _shellFor(userType);
  }

  Widget _shellFor(UserType userType) {
    if (userType == UserType.superAdmin) {
      return DeferredModuleLoader(
        moduleName: 'Admin Portal',
        loader: admin_module.loadLibrary,
        builder: () => admin_module.SuperAdminVerificationScreen(),
      );
    }
    if (userType.isDoctor) {
      final docId = DoctorSession.loggedInDoctorId.isNotEmpty
          ? DoctorSession.loggedInDoctorId
          : 'doc-new';
      return DeferredModuleLoader(
        moduleName: 'Doctor Dashboard',
        loader: doctor_module.loadLibrary,
        builder: () => doctor_module.DoctorVerificationGate(doctorId: docId),
      );
    }
    if (userType.isMedicalStore || userType.isMedical) {
      return DeferredModuleLoader(
        moduleName: 'Pharmacy Dashboard',
        loader: pharmacy_module.loadLibrary,
        builder: () => pharmacy_module.MedicalStoreShell(),
      );
    }
    if (userType.isLab) {
      return DeferredModuleLoader(
        moduleName: 'Lab Dashboard',
        loader: lab_module.loadLibrary,
        builder: () => lab_module.LabShell(),
      );
    }
    if (userType.isAmbulance) {
      final ambId = AmbulanceSession.loggedInAmbulanceId.isNotEmpty
          ? AmbulanceSession.loggedInAmbulanceId
          : 'amb-new';
      final amb = AmbulanceStore.instance.findAmbulance(ambId) ??
          (AmbulanceStore.instance.registeredAmbulances.isNotEmpty
              ? AmbulanceStore.instance.registeredAmbulances.first
              : RegisteredAmbulance(
                  id: ambId,
                  serviceName: AmbulanceSession.loggedInServiceName.isNotEmpty
                      ? AmbulanceSession.loggedInServiceName
                      : 'Ambulance Service',
                  driverName: AmbulanceSession.loggedInDriverName.isNotEmpty
                      ? AmbulanceSession.loggedInDriverName
                      : '',
                  phone: '',
                  vehicleNumber: '',
                  city: '',
                  available: false,
                  verified: false,
                ));
      return DeferredModuleLoader(
        moduleName: 'Ambulance Dashboard',
        loader: ambulance_module.loadLibrary,
        builder: () => ambulance_module.AmbulanceShell(ambulance: amb),
      );
    }
    return DeferredModuleLoader(
      moduleName: 'Patient Dashboard',
      loader: patient_module.loadLibrary,
      builder: () => patient_module.PatientShell(),
    );
  }
}

class DeferredModuleLoader extends StatefulWidget {
  const DeferredModuleLoader({
    super.key,
    required this.loader,
    required this.builder,
    required this.moduleName,
  });

  final Future<void> Function() loader;
  final Widget Function() builder;
  final String moduleName;

  @override
  State<DeferredModuleLoader> createState() => _DeferredModuleLoaderState();
}

class _DeferredModuleLoaderState extends State<DeferredModuleLoader> {
  late Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = widget.loader();
  }

  void _retry() {
    setState(() {
      _loadFuture = widget.loader();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return widget.builder();
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 48,
                      color: Color(0xFFEF4444),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load ${widget.moduleName}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please check your internet connection and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.doctorBlue,
                      ),
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return const Scaffold(
          body: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF0D9488),
              ),
            ),
          ),
        );
      },
    );
  }
}
