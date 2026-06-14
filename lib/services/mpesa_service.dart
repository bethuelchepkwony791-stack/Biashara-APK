import 'package:flutter_mpesa_stk/flutter_mpesa_stk.dart';

class MpesaService {
  static Future<void> initiateSTKPush({
    required String phoneNumber,
    required double amount,
    required String accountReference,
    required String transactionDesc,
  }) async {
    // Convert phone number to the required format (e.g., 254712345678)
    final formattedPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final finalPhone = formattedPhone.startsWith('0')
        ? '254${formattedPhone.substring(1)}'
        : formattedPhone;

    final stkPush = FlutterMpesaStk();
    await stkPush.pay(
      amount: amount.toString(),
      phoneNumber: finalPhone,
      consumerKey: 'ludiePGaslBVX49AvaAjzfE2AW6cGn7wMK8wJ1IVPRr4ULTk',
      consumerSecret: 'nTUwZy8fVzrAsGOAbrclOt8UEramFcQBpXEbLCDOhLxOx840KhVpjTCnQLNixmLC',
      passKey: 'YOUR_PASSKEY',
      shortCode: '174379',
      accountReference: accountReference,
      transactionDesc: transactionDesc,
    );
  }
}