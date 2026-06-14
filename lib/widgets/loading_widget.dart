import 'package:flutter/material.dart';

class LoadingWidget extends StatelessWidget {
  final String? message;
  
  const LoadingWidget({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
          ),
          const SizedBox(height: 16),
          Text(
            message ?? 'Loading...',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}