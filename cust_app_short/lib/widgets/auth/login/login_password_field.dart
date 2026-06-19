import 'package:flutter/material.dart';
import '../../../config/jago_theme.dart';

class LoginPasswordField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool showPassword;
  final VoidCallback onToggleVisibility;
  final VoidCallback onSubmit;

  const LoginPasswordField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.showPassword,
    required this.onToggleVisibility,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).inputDecorationTheme;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: !showPassword,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      style: JT.subtitle1.copyWith(color: JT.textPrimary),
      decoration: InputDecoration(
        hintText: 'Password',
        hintStyle: theme.hintStyle ?? JT.body.copyWith(color: JT.textTertiary),
        filled: true,
        fillColor: JT.bg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: JT.spacing16,
          vertical: JT.spacing16,
        ),
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: JT.textSecondary,
          size: 20,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: JT.textTertiary,
            size: 20,
          ),
          onPressed: onToggleVisibility,
        ),
        border: _border(),
        enabledBorder: _border(),
        focusedBorder: _border(focused: true),
      ),
    );
  }

  OutlineInputBorder _border({bool focused = false}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(JT.radiusMd),
      borderSide: BorderSide(
        color: focused ? JT.primary : JT.border,
        width: focused ? 1.6 : 1.2,
      ),
    );
  }
}
