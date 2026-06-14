const admin = require('firebase-admin');

// Replace with the path to your service account JSON file
const serviceAccount = require('./path-to-your-service-account-key.json');

// Initialize Firebase Admin SDK
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function deleteCollection(collectionPath, batchSize = 100) {
  const collectionRef = db.collection(collectionPath);
  const snapshot = await collectionRef.limit(batchSize).get();

  if (snapshot.empty) {
    console.log(`✅ Collection '${collectionPath}' is empty or already deleted.`);
    return;
  }

  const batch = db.batch();
  snapshot.docs.forEach((doc) => {
    batch.delete(doc.ref);
  });
  await batch.commit();

  console.log(`🗑️ Deleted ${snapshot.size} documents from '${collectionPath}'.`);
  // Recursively delete remaining documents
  await deleteCollection(collectionPath, batchSize);
}

async function reset() {
  console.log('🔥 Starting Firestore reset...');

  // Delete system/firstUser document
  const firstUserRef = db.collection('system').doc('firstUser');
  const doc = await firstUserRef.get();
  if (doc.exists) {
    await firstUserRef.delete();
    console.log('✅ Deleted system/firstUser document.');
  } else {
    console.log('ℹ️ system/firstUser document does not exist.');
  }

  // Delete all documents in 'users' collection
  await deleteCollection('users');

  console.log('✨ Reset complete. All users and the firstUser flag have been removed.');
  process.exit(0);
}

reset().catch((err) => {
  console.error('❌ Error during reset:', err);
  process.exit(1);
});