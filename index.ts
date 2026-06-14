import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import axios from 'axios';

admin.initializeApp();

// Your M‑Pesa sandbox credentials (store these in environment variables!)
const CONSUMER_KEY = 'ludiePGaslBVX49AvaAjzfE2AW6cGn7wMK8wJ1IVPRr4ULTk';
const CONSUMER_SECRET = 'nTUwZy8fVzrAsGOAbrclOt8UEramFcQBpXEbLCDOhLxOx840KhVpjTCnQLNixmLC';
const PASSKEY = 'YOUR_PASSKEY';
const SHORTCODE = '174379';       // sandbox shortcode

// Helper: Get OAuth token
async function getAccessToken(): Promise<string> {
  const auth = Buffer.from(`${CONSUMER_KEY}:${CONSUMER_SECRET}`).toString('base64');
  const response = await axios.get(
    'https://sandbox.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials',
    { headers: { Authorization: `Basic ${auth}` } }
  );
  return response.data.access_token;
}

// 2.3.1 Register the callback URLs (run once)
export const registerUrls = functions.https.onRequest(async (req, res) => {
  const token = await getAccessToken();
  const callbackUrl = 'https://us-central1-YOUR_biashara_os.cloudfunctions.net/mpesaCallback';
  const result = await axios.post(
    'https://sandbox.safaricom.co.ke/mpesa/c2b/v1/registerurl',
    {
      ShortCode: SHORTCODE,
      ResponseType: 'Completed',
      ConfirmationURL: callbackUrl,
      ValidationURL: callbackUrl,
    },
    { headers: { Authorization: `Bearer ${token}` } }
  );
  res.status(200).send(result.data);
});

// 2.3.2 The main webhook that M‑Pesa will call
export const mpesaCallback = functions.https.onRequest(async (req, res) => {
  try {
    const { Body } = req.body;
    const transaction = Body.stkCallback;
    
    // Only proceed if payment was successful
    if (transaction.ResultCode !== 0) {
      console.warn('Payment not successful', transaction.ResultDesc);
      res.status(200).send('OK');
      return;
    }

    const phone = transaction.CallbackMetadata?.Item?.find((i: any) => i.Name === 'PhoneNumber')?.Value;
    const amount = transaction.CallbackMetadata?.Item?.find((i: any) => i.Name === 'Amount')?.Value;
    const transactionId = transaction.CheckoutRequestID;

    // 1. Find the customer by phone number
    const customerSnapshot = await admin.firestore()
      .collection('customers')
      .where('phone', '==', phone)
      .limit(1)
      .get();

    if (customerSnapshot.empty) {
      console.warn(`No customer found with phone ${phone}`);
      res.status(200).send('OK');
      return;
    }

    const customerDoc = customerSnapshot.docs[0];
    const currentDebt = customerDoc.data().debtAmount || 0;

    // 2. Update debt
    const newDebt = Math.max(0, currentDebt - amount);
    await customerDoc.ref.update({ debtAmount: newDebt });

    // 3. Store payment in a sub‑collection (history)
    await customerDoc.ref.collection('payments').add({
      amount,
      transactionId,
      phone,
      date: admin.firestore.FieldValue.serverTimestamp(),
      status: 'completed',
    });

    console.log(`✅ Payment of KES ${amount} recorded for ${phone}. New debt: KES ${newDebt}`);
    res.status(200).send('OK');
  } catch (error) {
    console.error('Callback error:', error);
    res.status(500).send('Internal Server Error');
  }
});