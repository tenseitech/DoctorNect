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
  } catch (error) {
    console.error('Error writing to Firestore:', error);
    process.exit(1);
  }
}

seedDemoAccounts();
