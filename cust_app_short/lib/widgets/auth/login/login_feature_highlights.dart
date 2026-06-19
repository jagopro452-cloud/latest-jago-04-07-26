import 'package:flutter/material.dart';
import '../../../config/jago_theme.dart';

class LoginFeatureHighlights extends StatelessWidget {
  const LoginFeatureHighlights({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: const [
        Expanded(
          child: _FeatureItem(
            icon: Icons.shield_outlined,
            title: 'Safe & Secure',
            subtitle: 'Your safety is our priority',
          ),
        ),
        SizedBox(width: JT.spacing8),
        Expanded(
          child: _FeatureItem(
            icon: Icons.access_time_rounded,
            title: 'Quick Rides',
            subtitle: 'Book a ride in just a few taps',
          ),
        ),
        SizedBox(width: JT.spacing8),
        Expanded(
          child: _FeatureItem(
            icon: Icons.location_on_outlined,
            title: 'Anywhere',
            subtitle: 'Reliable rides, anytime, anywhere',
          ),
        ),
      ],
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: JT.primary, size: 22),
        const SizedBox(height: JT.spacing8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: JT.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: JT.textPrimary,
          ),
        ),
        const SizedBox(height: JT.spacing4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: JT.caption.copyWith(fontSize: 10, height: 1.3),
        ),
      ],
    );
  }
}
