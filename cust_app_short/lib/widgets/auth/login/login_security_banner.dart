import 'package:flutter/material.dart';
import '../../../config/jago_theme.dart';
import 'login_mode_switcher.dart';

class LoginSecurityBanner extends StatelessWidget {
  final LoginMode mode;

  const LoginSecurityBanner({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    final isOtp = mode == LoginMode.otp;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: JT.spacing16,
        vertical: JT.spacing12,
      ),
      decoration: BoxDecoration(
        color: JT.surfaceAlt,
        borderRadius: BorderRadius.circular(JT.radiusMd),
        border: Border.all(color: JT.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: JT.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(JT.radiusMd),
            ),
            child: Icon(
              isOtp ? Icons.sms_outlined : Icons.shield_outlined,
              color: JT.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: JT.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOtp ? 'Secure OTP sign in' : 'Secure password sign in only',
                  style: JT.subtitle2.copyWith(
                    fontWeight: FontWeight.w700,
                    color: JT.textPrimary,
                  ),
                ),
                const SizedBox(height: JT.spacing4),
                Text(
                  isOtp
                      ? 'OTP will be sent to your mobile number'
                      : 'Your security is our priority',
                  style: JT.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
