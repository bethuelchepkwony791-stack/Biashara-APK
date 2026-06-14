const admin = require('firebase-admin');

// Initialize Admin SDK with your service account
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function migrate() {
  const defaultTenantId = 'default_tenant';

  // Create the default tenant document
  const tenantRef = db.collection('tenants').doc(defaultTenantId);
  const tenantDoc = await tenantRef.get();
  if (!tenantDoc.exists) {
    await tenantRef.set({ name: 'Default Business', createdAt: admin.firestore.FieldValue.serverTimestamp() });
    console.log('Created default tenant');
  }

  let updated = 0;

  // 1. Customers
  const customers = await db.collection('customers').get();
  for (const doc of customers.docs) {
    const data = doc.data();
    if (!data.tenantId) {
      await doc.ref.update({ tenantId: defaultTenantId });
      updated++;
      console.log(`Updated customer ${doc.id}`);
    }
  }

  // 2. Transactions
  const transactions = await db.collection('transactions').get();
  for (const doc of transactions.docs) {
    const data = doc.data();
    if (!data.tenantId) {
      await doc.ref.update({ tenantId: defaultTenantId });
      updated++;
      console.log(`Updated transaction ${doc.id}`);
    }
  }

  // 3. Users
  const users = await db.collection('users').get();
  for (const doc of users.docs) {
    const data = doc.data();
    if (!data.tenantId) {
      await doc.ref.update({ tenantId: defaultTenantId });
      updated++;
      console.log(`Updated user ${doc.id}`);
    }
  }

  console.log(`Migration complete. Updated ${updated} documents.`);
}

migrate().catch(console.error);