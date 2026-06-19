import 'package:flutter/material.dart';
import '../../../config/jago_theme.dart';

enum LoginMode { otp, phonePassword }

class LoginModeSwitcher extends StatelessWidget {
  final LoginMode mode;
  final ValueChanged<LoginMode> onModeChanged;

  const LoginModeSwitcher({
    super.key,
    required this.mode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(JT.spacing8),
      decoration: BoxDecoration(
        color: JT.primaryLight,
        borderRadius: BorderRadius.circular(JT.radiusMd),
      ),
      child: Row(
        children: [
          _segment('Password', LoginMode.phonePassword),
          _segment('OTP Login', LoginMode.otp),
        ],
      ),
    );
  }

  Widget _segment(String label, LoginMode value) {
    final selected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onModeChanged(value),
        child: AnimatedContainer(
          duration: JT.animationMedium,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? JT.bg : Colors.transparent,
            borderRadius: BorderRadius.circular(JT.radiusMd),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: JT.primary.withValues(alpha: 0.12),
                      blurRadius: JT.spacing8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: JT.subtitle2.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? JT.primary : JT.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
