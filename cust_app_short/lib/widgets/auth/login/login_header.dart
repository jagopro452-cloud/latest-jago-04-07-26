import 'package:flutter/material.dart';
import '../../../config/jago_theme.dart';

class LoginHeader extends StatelessWidget {
  const LoginHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        JT.spacing24,
        JT.spacing12,
        JT.spacing24,
        JT.spacing8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JT.logoBlue(height: 42),
          const SizedBox(height: JT.spacing8),
          Text(
            'Move Smarter.',
            style: JT.subtitle2.copyWith(
              fontWeight: FontWeight.w500,
              color: JT.textPrimary.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: JT.spacing16),
          Text(
            'Welcome Back',
            style: JT.h1.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: JT.spacing8),
          Text(
            'Login to continue your journey with JAGO',
            style: JT.subtitle2,
          ),
        ],
      ),
    );
  }
}
