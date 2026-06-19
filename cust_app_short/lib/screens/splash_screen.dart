import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/jago_theme.dart';
import '../services/auth_service.dart';
import '../services/secure_token_store.dart';
import 'auth/login_screen.dart';
import 'main_screen.dart';
import 'onboarding/onboarding_screen.dart';
import 'onboarding/terms_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _logoCtrl;
  late AnimationController _textCtrl;
  late AnimationController _cityCtrl;
  late AnimationController _progressCtrl;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<double> _textSlide;
  late Animation<double> _cityOpacity;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFE8F2FF),
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.6)));

    _textCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn));
    _textSlide = Tween<double>(begin: 12.0, end: 0.0)
        .animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));

    _cityCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _cityOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _cityCtrl, curve: Curves.easeIn));

    _progressCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
      ..forward();

    _runSequence();
    _navigate();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    _cityCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    _logoCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    _textCtrl.forward();
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _cityCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 3500));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final termsAccepted = prefs.getBool('terms_accepted') ?? false;
    if (!termsAccepted) {
      if (!mounted) return;
      Navigator.pushReplacement(context, PageRouteBuilder(
        pageBuilder: (_, __, ___) => const TermsScreen(),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ));
      return;
    }
    final onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
    final token = await SecureTokenStore.read();
    if (!mounted) return;

    Widget destination;
    if (!onboardingSeen) {
      destination = const OnboardingScreen();
    } else if (token != null && token.isNotEmpty) {
      final profile = await AuthService.getProfile();
      if (!mounted) return;
      if (profile != null) {
        destination = const MainScreen();
      } else {
        await AuthService.logout();
        destination = const LoginScreen();
      }
    } else {
      destination = const LoginScreen();
    }

    if (!mounted) return;
    Navigator.pushReplacement(context, PageRouteBuilder(
      pageBuilder: (_, __, ___) => destination,
      transitionDuration: const Duration(milliseconds: 800),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cityHeight = size.height * 0.38;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xFFF5FAFF),
                    Color(0xFFE8F2FF),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          AnimatedBuilder(
            animation: _cityCtrl,
            builder: (_, child) => Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: cityHeight,
              child: Opacity(opacity: _cityOpacity.value, child: child),
            ),
            child: const SizedBox.expand(
              child: CustomPaint(painter: _SplashCityscapePainter()),
            ),
          ),

          Positioned(
            top: size.height * 0.30,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _logoCtrl,
                  builder: (_, child) => Transform.scale(
                    scale: _logoScale.value,
                    child: Opacity(opacity: _logoOpacity.value, child: child),
                  ),
                  child: JT.logoBlue(height: 88),
                ),
                const SizedBox(height: 18),
                AnimatedBuilder(
                  animation: _textCtrl,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, _textSlide.value),
                    child: Opacity(opacity: _textOpacity.value, child: child),
                  ),
                  child: Text(
                    'Move Smarter.',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0D47A1),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 36,
            child: AnimatedBuilder(
              animation: _textCtrl,
              builder: (_, child) => Opacity(opacity: _textOpacity.value, child: child!),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: size.width * 0.18),
                    child: AnimatedBuilder(
                      animation: _progressCtrl,
                      builder: (_, __) => ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: _progressCtrl.value,
                          minHeight: 3,
                          backgroundColor: const Color(0xFFD1D5DB),
                          valueColor: const AlwaysStoppedAnimation<Color>(JT.primary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Loading...',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashCityscapePainter extends CustomPainter {
  const _SplashCityscapePainter();

  static const _buildingColor = Color(0xFFB8D4F5);
  static const _buildingLight = Color(0xFFD4E8FA);
  static const _roadColor = Color(0xFFC5DBF5);
  static const _pinColor = JT.primary;

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * 0.42;
    final centerX = size.width * 0.5;

    _drawSkyline(canvas, size, horizonY);
    _drawRoad(canvas, size, horizonY, centerX);
    _drawMapPin(canvas, Offset(centerX, horizonY - 2));
  }

  void _drawSkyline(Canvas canvas, Size size, double horizonY) {
    final buildings = <_Building>[
      const _Building(0.00, 0.18, 0.55),
      const _Building(0.08, 0.14, 0.42),
      const _Building(0.15, 0.20, 0.68),
      const _Building(0.24, 0.16, 0.48),
      const _Building(0.32, 0.22, 0.72),
      const _Building(0.40, 0.18, 0.58),
      const _Building(0.48, 0.26, 0.82),
      const _Building(0.58, 0.20, 0.65),
      const _Building(0.66, 0.16, 0.50),
      const _Building(0.74, 0.22, 0.75),
      const _Building(0.82, 0.18, 0.60),
      const _Building(0.90, 0.14, 0.45),
    ];

    for (var i = 0; i < buildings.length; i++) {
      final b = buildings[i];
      final left = size.width * b.x;
      final width = size.width * b.w;
      final height = size.height * b.h;
      final top = horizonY - height;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, height),
        const Radius.circular(2),
      );
      final paint = Paint()
        ..color = i.isEven ? _buildingColor : _buildingLight
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rect, paint);

      // Window dots
      final windowPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.fill;
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 2; col++) {
          if ((i + row + col) % 2 == 0) continue;
          canvas.drawRect(
            Rect.fromLTWH(
              left + width * (0.25 + col * 0.35),
              top + height * (0.15 + row * 0.22),
              width * 0.12,
              height * 0.08,
            ),
            windowPaint,
          );
        }
      }
    }

    // Soft cloud blend at horizon
    final cloudPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, horizonY - 30, size.width, 60));
    canvas.drawRect(Rect.fromLTWH(0, horizonY - 30, size.width, 60), cloudPaint);
  }

  void _drawRoad(Canvas canvas, Size size, double horizonY, double centerX) {
    final roadPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(centerX - 8, horizonY)
      ..lineTo(centerX + 8, horizonY)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(roadPath, Paint()..color = _roadColor);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 6; i++) {
      final t = (i + 1) / 7;
      final y = horizonY + (size.height - horizonY) * t;
      final halfWidth = 8 + (size.width * 0.48 - 8) * t;
      canvas.drawLine(
        Offset(centerX - halfWidth, y),
        Offset(centerX + halfWidth, y),
        linePaint..strokeWidth = 1.5 + t * 1.5,
      );
    }

    // Center dashed perspective line
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final dashPath = Path();
    for (var i = 0; i < 8; i++) {
      final t1 = i / 8;
      final t2 = t1 + 0.04;
      dashPath.moveTo(centerX, horizonY + (size.height - horizonY) * t1);
      dashPath.lineTo(centerX, horizonY + (size.height - horizonY) * t2);
    }
    canvas.drawPath(dashPath, dashPaint);
  }

  void _drawMapPin(Canvas canvas, Offset tip) {
    const pinH = 28.0;
    const pinW = 18.0;

    final pinPath = Path()
      ..moveTo(tip.dx, tip.dy + pinH * 0.35)
      ..cubicTo(
        tip.dx - pinW, tip.dy - pinH * 0.1,
        tip.dx - pinW * 0.55, tip.dy - pinH,
        tip.dx, tip.dy - pinH * 0.85,
      )
      ..cubicTo(
        tip.dx + pinW * 0.55, tip.dy - pinH,
        tip.dx + pinW, tip.dy - pinH * 0.1,
        tip.dx, tip.dy + pinH * 0.35,
      )
      ..close();

    canvas.drawPath(pinPath, Paint()..color = _pinColor);

    canvas.drawCircle(
      Offset(tip.dx, tip.dy - pinH * 0.55),
      5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SplashCityscapePainter oldDelegate) => false;
}

class _Building {
  final double x;
  final double w;
  final double h;

  const _Building(this.x, this.w, this.h);
}
