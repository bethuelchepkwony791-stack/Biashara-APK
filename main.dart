import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Preload shaders (optional for web)
  if (kIsWeb) {
    await Future.wait([
      PaintingBinding.instance.shaderWarmUp,
    ]);
  }
  runApp(const BiasharaOS());
}