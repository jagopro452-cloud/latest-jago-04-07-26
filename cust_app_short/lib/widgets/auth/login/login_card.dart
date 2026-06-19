import 'package:flutter/material.dart';
import '../../../config/jago_theme.dart';

class LoginCard extends StatelessWidget {
  final Widget child;

  const LoginCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JT.bg,
        borderRadius: BorderRadius.circular(JT.radiusLg),
        boxShadow: [
          BoxShadow(
            color: JT.primary.withValues(alpha: 0.10),
            blurRadius: JT.spacing24,
            offset: const Offset(0, JT.spacing12),
          ),
          ...JT.shadowSm,
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(JT.spacing24),
        child: child,
      ),
    );
  }
}
