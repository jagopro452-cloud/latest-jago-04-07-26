import 'package:flutter/material.dart';
import '../../../config/jago_theme.dart';

class LoginCreateAccountTile extends StatelessWidget {
  final VoidCallback onTap;

  const LoginCreateAccountTile({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(JT.radiusMd),
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: JT.spacing16,
            vertical: JT.spacing16,
          ),
          decoration: BoxDecoration(
            color: JT.surfaceAlt,
            borderRadius: BorderRadius.circular(JT.radiusMd),
            border: Border.all(color: JT.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: JT.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(JT.radiusMd),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: JT.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: JT.spacing12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: JT.subtitle2.copyWith(color: JT.textPrimary),
                    children: [
                      const TextSpan(text: "Don't have an account? "),
                      TextSpan(
                        text: 'Create Account',
                        style: JT.subtitle2.copyWith(
                          fontWeight: FontWeight.w700,
                          color: JT.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: JT.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
