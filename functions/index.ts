const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.migrateToMultiTenant = functions.https.onRequest(async (req, res) => {
  // Only allow if a secret token is provided (basic security)
  const token = req.query.token;
  if (token !== 'abc123') {
    res.status(403).send('Forbidden');
    return;
  }

  const defaultTenantId = 'default_tenant';
  const tenantRef = admin.firestore().collection('tenants').doc(defaultTenantId);
  const tenantDoc = await tenantRef.get();
  if (!tenantDoc.exists) {
    await tenantRef.set({ name: 'Default Business', createdAt: admin.firestore.FieldValue.serverTimestamp() });
  }

  let updatedCount = 0;

  // Migrate customers
  const customers = await admin.firestore().collection('customers').get();
  for (const doc of customers.docs) {
    if (!doc.data().tenantId) {
      await doc.ref.update({ tenantId: defaultTenantId });
      updatedCount++;
    }
  }

  // Migrate transactions
  const transactions = await admin.firestore().collection('transactions').get();
  for (const doc of transactions.docs) {
    if (!doc.data().tenantId) {
      await doc.ref.update({ tenantId: defaultTenantId });
      updatedCount++;
    }
  }

  // Migrate users
  const users = await admin.firestore().collection('users').get();
  for (const doc of users.docs) {
    if (!doc.data().tenantId) {
      await doc.ref.update({ tenantId: defaultTenantId });
      updatedCount++;
    }
  }

  res.send(`Migration complete. Updated ${updatedCount} documents.`);
});