import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/jago_theme.dart';

class LoginPhoneField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool moveToPasswordOnSubmit;
  final VoidCallback onDone;

  const LoginPhoneField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.moveToPasswordOnSubmit,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).inputDecorationTheme;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.phone,
      textInputAction:
          moveToPasswordOnSubmit ? TextInputAction.next : TextInputAction.done,
      onSubmitted: (_) => onDone(),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      style: JT.subtitle1.copyWith(
        fontWeight: FontWeight.w600,
        color: JT.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'Mobile number',
        hintStyle: theme.hintStyle ?? JT.body.copyWith(color: JT.textTertiary),
        filled: true,
        fillColor: JT.bg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: JT.spacing16,
          vertical: JT.spacing16,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: JT.spacing12, right: JT.spacing4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '+91',
                style: JT.subtitle2.copyWith(
                  fontWeight: FontWeight.w600,
                  color: JT.textPrimary,
                ),
              ),
              const SizedBox(width: JT.spacing8),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: JT.textSecondary,
              ),
              const SizedBox(width: JT.spacing8),
              Container(width: 1, height: 22, color: JT.border),
              const SizedBox(width: JT.spacing8),
              const Icon(Icons.phone_outlined, size: 18, color: JT.textSecondary),
            ],
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
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
