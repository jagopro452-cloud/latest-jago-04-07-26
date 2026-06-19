import 'package:flutter/material.dart';
import '../../../config/jago_theme.dart';

class LoginOrDivider extends StatelessWidget {
  const LoginOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: JT.border, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: JT.spacing12),
          child: Text('or', style: JT.caption),
        ),
        const Expanded(child: Divider(color: JT.border, thickness: 1)),
      ],
    );
  }
}
