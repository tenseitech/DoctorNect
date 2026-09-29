const admin = require('firebase-admin');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

// Initialize admin SDK using default credentials
const projectId = 'medibond-45fad';

admin.initializeApp({
  projectId: projectId
});

const db = getFirestore();

async function seedDemoAccounts() {
  const docRef = db.collection('app_config').doc('demo_accounts');
  
  const config = {
    demoOtp: "000000",
    demoPhones: {
      patient: ["7058809803"],
      doctor: ["7666892394"],
      medicalStore: ["9359503874"],
      lab: ["9409858233"],
      ambulance: ["9307583929"]
    },
    updatedAt: FieldValue.serverTimestamp()
  };

  try {
    console.log(`Writing demo_accounts to ${projectId} Firestore...`);
    await docRef.set(config, { merge: true });
    console.log('Successfully seeded demo_accounts config.');

    // Seed fully verified demo doctor account
    const doctorPhone = "7666892394";
    const doctorId = "demo_doctor_7666892394";
    const doctorEmail = "doctor.demo@doctornect.com";
    const doctorDisplayName = "Dr. Demo Doctor";

    // Check if demo doctor user already exists in users collection
    let doctorUid = `demo_user_${doctorPhone}`;
    const userSnapshot = await db.collection('users').where('mobile', 'in', [doctorPhone, `+91${doctorPhone}`]).limit(1).get();
    if (!userSnapshot.empty) {
      doctorUid = userSnapshot.docs[0].id;
    }

    const doctorProfile = {
      doctorId: doctorId,
      ownerUid: doctorUid,
      name: doctorDisplayName,
      fullName: doctorDisplayName,
      mobile: doctorPhone,
      phone: doctorPhone,
      email: doctorEmail,
      qualification: "MBBS, MD (General Medicine)",
      specialization: "General Medicine (Internal Medicine)",
      councilNumber: `MCI-${doctorPhone}`,
      stateCouncil: "Maharashtra Medical Council",
      registrationYear: 2016,
      yearsExperience: 10,
      clinicName: "Dr. Demo Healthcare Clinic",
      clinicType: "Private Clinic",
      addressLine1: "Suite 101, Medical Enclave",
      city: "Mumbai",
      state: "Maharashtra",
      country: "India",
      pincode: "400001",
      verified: true,
      verificationStatus: "verified",
      status: "approved",
      kycSubmitted: true,
      profileCompleted: true,
      deactivated: false,
      rating: 4.9,
      reviewCount: 24,
      advanceBookingDays: 7,
      autoAcceptAppointments: true,
      appointmentReminders: true,
      registrationCertificate: "https://storage.googleapis.com/demo/medical_council_cert.pdf",
      idProof: "https://storage.googleapis.com/demo/doctor_id_proof.pdf",
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    };

    const userProfile = {
      role: "doctor",
      profileId: doctorId,
      displayName: doctorDisplayName,
      email: doctorEmail,
      mobile: doctorPhone,
      phone: doctorPhone,
      verified: true,
      verificationStatus: "verified",
      status: "approved",
      profileCompleted: true,
      mobileVerified: true,
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    };

    console.log(`Seeding fully verified demo doctor (${doctorPhone}) to Firestore...`);
    await db.collection('doctors').doc(doctorId).set(doctorProfile, { merge: true });
    await db.collection('users').doc(doctorUid).set(userProfile, { merge: true });
    console.log(`Successfully seeded fully verified demo doctor (${doctorId} / ${doctorUid}).`);

    // Seed fully verified demo pharmacy / medical store account (9359503874)
    const pharmacyPhone = "9359503874";
    const pharmacyProfileId = "ms1784184914244";
    const pharmacyDisplayName = "KD Rx Pharma";
    const pharmacyEmail = "pharmacy.demo@doctornect.com";

    let pharmacyUid = "EdaUG8nTgbRjGLgZGAmDi3vWwhO2";
    const pharmacyUserSnapshot = await db.collection('users').where('mobile', 'in', [pharmacyPhone, `+91${pharmacyPhone}`]).limit(1).get();
    if (!pharmacyUserSnapshot.empty) {
      pharmacyUid = pharmacyUserSnapshot.docs[0].id;
    }

    const pharmacyStoreData = {
      storeId: pharmacyProfileId,
      ownerUid: pharmacyUid,
      storeName: pharmacyDisplayName,
      name: pharmacyDisplayName,
      mobile: pharmacyPhone,
      phone: `+91${pharmacyPhone}`,
      email: pharmacyEmail,
      city: "Nagpur",
      verified: true,
      verificationStatus: "verified",
      status: "approved",
      profileCompleted: true,
      updatedAt: FieldValue.serverTimestamp(),
    };

    const pharmacyUserData = {
      role: "medicalStore",
      profileId: pharmacyProfileId,
      displayName: pharmacyDisplayName,
      email: pharmacyEmail,
      mobile: pharmacyPhone,
      phone: pharmacyPhone,
      verified: true,
      verificationStatus: "verified",
      status: "approved",
      profileCompleted: true,
      mobileVerified: true,
      updatedAt: FieldValue.serverTimestamp(),
    };

    console.log(`Seeding fully verified demo pharmacy (${pharmacyPhone}) to Firestore...`);
    await db.collection('medical_stores').doc(pharmacyProfileId).set(pharmacyStoreData, { merge: true });
    await db.collection('users').doc(pharmacyUid).set(pharmacyUserData, { merge: true });
    console.log(`Successfully seeded fully verified demo pharmacy (${pharmacyProfileId} / ${pharmacyUid}).`);

    // Seed fully verified demo lab account (9409858233)
    const labPhone = "9409858233";
    const labProfileId = "l1784185011933";
    const labDisplayName = "KD Labs";
    const labEmail = "lab.demo@doctornect.com";

    let labUid = "vMwQMBueSVUGpef1zzrN17gfT7y2";
    const labUserSnapshot = await db.collection('users').where('mobile', 'in', [labPhone, `+91${labPhone}`]).limit(1).get();
    if (!labUserSnapshot.empty) {
      labUid = labUserSnapshot.docs[0].id;
    }

    const labData = {
      labId: labProfileId,
      ownerUid: labUid,
      labName: labDisplayName,
      name: labDisplayName,
      mobile: labPhone,
      phone: `+91${labPhone}`,
      email: labEmail,
      city: "Nagpur",
      verified: true,
      verificationStatus: "verified",
      status: "approved",
      profileCompleted: true,
      updatedAt: FieldValue.serverTimestamp(),
    };

    const labUserData = {
      role: "lab",
      profileId: labProfileId,
      displayName: labDisplayName,
      email: labEmail,
      mobile: labPhone,
      phone: labPhone,
      verified: true,
      verificationStatus: "verified",
      status: "approved",
      profileCompleted: true,
      mobileVerified: true,
      updatedAt: FieldValue.serverTimestamp(),
    };

    console.log(`Seeding fully verified demo lab (${labPhone}) to Firestore...`);
    await db.collection('labs').doc(labProfileId).set(labData, { merge: true });
    await db.collection('users').doc(labUid).set(labUserData, { merge: true });
    console.log(`Successfully seeded fully verified demo lab (${labProfileId} / ${labUid}).`);

    // Seed fully verified demo ambulance account (9307583929)
    const ambulancePhone = "9307583929";
    const ambulanceProfileId = "amb-reg-1787919627226";
    const ambulanceDisplayName = "Demo Ambulance";
    const ambulanceDriverName = "Driver";
    const ambulanceAuthUid = "CTVzgkpdnjUs0uDDr5rWdVV3iWF2";

    const ambulanceData = {
      id: ambulanceProfileId,
      ambulanceId: ambulanceProfileId,
      authUid: ambulanceAuthUid,
      serviceName: ambulanceDisplayName,
      driverName: ambulanceDriverName,
      phone: `+91${ambulancePhone}`,
      mobile: ambulancePhone,
      city: "Nagpur",
      ambulanceType: "bls",
      isAvailable: true,
      verified: true,
      verificationStatus: "verified",
      status: "approved",
      updatedAt: FieldValue.serverTimestamp(),
    };

    const ambulanceUserData = {
      role: "ambulance",
      profileId: ambulanceProfileId,
      displayName: ambulanceDisplayName,
      mobile: ambulancePhone,
      phone: ambulancePhone,
      verified: true,
      verificationStatus: "verified",
      status: "approved",
      profileCompleted: true,
      mobileVerified: true,
      updatedAt: FieldValue.serverTimestamp(),
    };

    console.log(`Seeding fully verified demo ambulance (${ambulancePhone}) to Firestore...`);
    await db.collection('ambulances').doc(ambulanceProfileId).set(ambulanceData, { merge: true });
    await db.collection('users').doc(ambulanceAuthUid).set(ambulanceUserData, { merge: true });
    await db.collection('users').doc(ambulanceProfileId).set(ambulanceUserData, { merge: true });
    console.log(`Successfully seeded fully verified demo ambulance (${ambulanceProfileId} / ${ambulanceAuthUid}).`);
  } catch (error) {
    console.error('Error writing to Firestore:', error);
    process.exit(1);
  }
}

seedDemoAccounts();
