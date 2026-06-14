import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'dart:io' show exit;
import 'login_screen.dart';
import 'auth_wrapper.dart';   // Keep for web navigator fallback if needed

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _clearFirestoreCache(BuildContext context) async {
    if (kIsWeb) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Clear Cache'),
          content: const Text('Reload page?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reload')),
          ],
        ),
      );
      if (confirm == true) {
        await FirebaseFirestore.instance.terminate();
        html.window.location.reload();
      }
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear Local Cache'),
        content: const Text('Cache cleared. App will restart.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Clear & Restart')),
        ],
      ),
    );
    if (confirm == true) {
      // ignore: use_build_context_synchronously
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
      try {
        await FirebaseFirestore.instance.terminate();
        await FirebaseFirestore.instance.clearPersistence();
        exit(0);
      } catch (e) { /* ignore */ }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), backgroundColor: Colors.green),
      body: ListView(
        children: [
          if (user != null)
            Card(
              margin: const EdgeInsets.all(16),
              child: ListTile(
                leading: const Icon(Icons.person, color: Colors.green),
                title: Text(user.email ?? 'No email'),
                subtitle: const Text('Logged in user'),
              ),
            ),
          const ListTile(leading: Icon(Icons.offline_bolt), title: Text('Offline Support'), subtitle: Text('Data is cached automatically when online.')),
          const Divider(),
          ListTile(leading: const Icon(Icons.delete_sweep, color: Colors.red), title: const Text('Clear Local Cache'), subtitle: const Text('Remove all cached Firestore data. App will restart.'), onTap: () => _clearFirestoreCache(context)),
          const Divider(),
          const ListTile(leading: Icon(Icons.info), title: Text('About'), subtitle: Text('BiasharaOS v1.5.0\nMulti‑tenant • Role‑based security • Offline support')),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout'),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              // Small delay to ensure sign‑out completes
              await Future.delayed(const Duration(milliseconds: 200));
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthWrapper()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}