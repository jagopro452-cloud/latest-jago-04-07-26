import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../config/jago_theme.dart';

class LoginBackground extends StatelessWidget {
  const LoginBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/login_bg.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  JT.primaryLight,
                  JT.surfaceAlt,
                  JT.bgSoft,
                ],
              ),
            ),
          ),
        ),
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
            child: Container(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0.15),
                Colors.white.withValues(alpha: 0.88),
              ],
              stops: const [0.0, 0.42, 0.72],
            ),
          ),
        ),
      ],
    );
  }
}
