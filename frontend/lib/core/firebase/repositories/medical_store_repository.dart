import '../../../features/pharmacy/models/pharmacy_models.dart';
import '../../supabase/repositories/supabase_pharmacy_repository.dart';

class MedicalStoreRepository {
  MedicalStoreRepository._();

  static final MedicalStoreRepository instance = MedicalStoreRepository._();

  Future<bool> isStoreVerified(String storeId) async {
    final store =
        await SupabasePharmacyRepository.instance.fetchMedicalStore(storeId);
    return store?.verified ?? false;
  }

  Future<List<MedicalStoreProfile>> fetchVerifiedStores({
    bool preferCache = true,
  }) async {
    return SupabasePharmacyRepository.instance.fetchVerifiedStores();
  }

  Future<MedicalStoreProfile?> fetchStoreById(String storeId) async {
    return SupabasePharmacyRepository.instance.fetchMedicalStore(storeId);
  }

  Future<void> updateStoreFields(
    String storeId, {
    String? storeName,
    String? ownerName,
    String? drugLicenseNumber,
    Map<String, dynamic>? address,
    String? phone,
    String? email,
    String? gstNumber,
    bool clearGstNumber = false,
  }) async {
    return SupabasePharmacyRepository.instance.updateMedicalStoreFields(
      storeId,
      storeName: storeName,
      ownerName: ownerName,
      drugLicenseNumber: drugLicenseNumber,
      address: address,
      phone: phone,
      email: email,
      gstNumber: gstNumber,
      clearGstNumber: clearGstNumber,
    );
  }
}
