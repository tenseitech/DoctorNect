import '../../supabase/repositories/supabase_lab_repository.dart';
import '../../supabase/supabase_bootstrap.dart';

/// Registered diagnostic lab profile.
class RegisteredLabProfile {
  const RegisteredLabProfile({
    required this.id,
    required this.labName,
    required this.address,
    required this.licenseNumber,
    this.phone = '',
    this.email = '',
    this.gstNumber,
    this.rating = 0,
    this.area = '',
    this.verified = false,
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.country = '',
    this.state = '',
    this.city = '',
    this.pincode = '',
  });

  final String id;
  final String labName;
  final String address;
  final String licenseNumber;
  final String phone;
  final String email;
  final String? gstNumber;
  final double rating;
  final String area;
  final bool verified;
  final String addressLine1;
  final String addressLine2;
  final String country;
  final String state;
  final String city;
  final String pincode;

  RegisteredLabProfile copyWith({
    String? labName,
    String? address,
    String? licenseNumber,
    String? phone,
    String? email,
    String? gstNumber,
    double? rating,
    String? area,
    bool? verified,
    String? addressLine1,
    String? addressLine2,
    String? country,
    String? state,
    String? city,
    String? pincode,
  }) {
    return RegisteredLabProfile(
      id: id,
      labName: labName ?? this.labName,
      address: address ?? this.address,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      gstNumber: gstNumber ?? this.gstNumber,
      rating: rating ?? this.rating,
      area: area ?? this.area,
      verified: verified ?? this.verified,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      country: country ?? this.country,
      state: state ?? this.state,
      city: city ?? this.city,
      pincode: pincode ?? this.pincode,
    );
  }
}

class LabRepository {
  LabRepository._();

  static final LabRepository instance = LabRepository._();

  Future<bool> isLabVerified(String labId) async {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) return false;
    try {
      final res = await SupabaseBootstrap.client
          .from('labs')
          .select('verified')
          .eq('lab_id', labId)
          .maybeSingle();
      return res?['verified'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<RegisteredLabProfile?> fetchLabById(
    String labId, {
    bool preferCache = true,
  }) async {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) return null;
    try {
      final res = await SupabaseBootstrap.client
          .from('labs')
          .select()
          .eq('lab_id', labId)
          .maybeSingle();
      if (res == null) return null;
      return _fromRow(labId, res);
    } catch (_) {
      return null;
    }
  }

  Future<List<RegisteredLabProfile>> fetchVerifiedLabs({
    bool preferCache = true,
  }) async {
    final partners =
        await SupabaseLabRepository.instance.fetchVerifiedLabs();
    if (partners.isEmpty) return const [];
    final profiles = <RegisteredLabProfile>[];
    for (final partner in partners) {
      final profile = await fetchLabById(
        partner.id ?? '',
        preferCache: preferCache,
      );
      if (profile != null && profile.verified) {
        profiles.add(profile);
      }
    }
    return profiles;
  }

  RegisteredLabProfile? _fromRow(String id, Map<String, dynamic> row) {
    try {
      final line1 = row['address_line1'] as String? ?? '';
      final line2 = row['address_line2'] as String? ?? '';
      final city = row['city'] as String? ?? '';
      final state = row['state'] as String? ?? '';
      final pin = row['pincode'] as String? ?? '';
      final parts = [line1, line2, city, state, pin].where((e) => e.isNotEmpty);
      return RegisteredLabProfile(
        id: row['lab_id'] as String? ?? id,
        labName: row['lab_name'] as String? ?? row['name'] as String? ?? '',
        address: parts.join(', '),
        addressLine1: line1,
        addressLine2: line2,
        country: row['country'] as String? ?? '',
        state: state,
        city: city,
        pincode: pin,
        licenseNumber: row['license_number'] as String? ?? '',
        phone: row['phone'] as String? ?? '',
        email: row['email'] as String? ?? '',
        gstNumber: _optionalGst(row['gst_number'] as String?),
        rating: (row['rating'] as num?)?.toDouble() ?? 0,
        area: city.isNotEmpty ? city : (row['area'] as String? ?? ''),
        verified: row['verified'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _optionalGst(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> updateLabFields(
    String labId, {
    String? labName,
    String? licenseNumber,
    Map<String, dynamic>? address,
    String? phone,
    String? email,
    String? gstNumber,
    bool clearGstNumber = false,
  }) async {
    if (!SupabaseBootstrap.isReady || labId.isEmpty) return;

    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (labName != null) {
      updates['lab_name'] = labName;
      updates['name'] = labName;
    }
    if (licenseNumber != null) updates['license_number'] = licenseNumber;
    if (address != null) {
      if (address['country'] != null) updates['country'] = address['country'];
      if (address['state'] != null) updates['state'] = address['state'];
      if (address['city'] != null) updates['city'] = address['city'];
      if (address['addressLine1'] != null) {
        updates['address_line1'] = address['addressLine1'];
      }
      if (address['addressLine2'] != null) {
        updates['address_line2'] = address['addressLine2'];
      }
      if (address['pinCode'] != null) updates['pincode'] = address['pinCode'];
    }
    if (phone != null) updates['phone'] = phone;
    if (email != null) updates['email'] = email.trim().toLowerCase();
    if (clearGstNumber) {
      updates['gst_number'] = null;
    } else if (gstNumber != null) {
      updates['gst_number'] = gstNumber;
    }

    if (updates.length == 1) return;

    await SupabaseBootstrap.client
        .from('labs')
        .update(updates)
        .eq('lab_id', labId);
  }
}
