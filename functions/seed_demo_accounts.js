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
  } catch (error) {
    console.error('Error writing to Firestore:', error);
    process.exit(1);
  }
}

seedDemoAccounts();
