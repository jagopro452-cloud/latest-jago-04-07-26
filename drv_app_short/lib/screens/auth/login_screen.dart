import 'package:flutter/material.dart';
import '../../config/jago_theme.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import '../home/home_screen.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;

  late final AnimationController _cardCtrl;
  late final Animation<Offset> _cardSlide;
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoFade;

  static const _blue = JT.primary;
  static const _dark = Color(0xFF080F1E);

  @override
  void initState() {
    super.initState();
    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _cardSlide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));
    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _logoFade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut));
    _logoCtrl.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _cardCtrl.forward();
    });
  }

  @override
  void dispose() {
    _cardCtrl.dispose();
    _logoCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontWeight: FontWeight.w400, color: Colors.white, fontSize: 13)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _loginWithPassword() async {
    final phone = _phoneCtrl.text.trim();
    final pass = _passwordCtrl.text;
    if (phone.length != 10) {
      _snack('Enter a valid 10-digit mobile number', error: true);
      return;
    }
    if (pass.length < 8) {
      _snack('Password must be at least 8 characters', error: true);
      return;
    }
    setState(() => _loading = true);
    final res = await AuthService.loginWithPassword(phone, pass);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true || res['token'] != null) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
    } else {
      _snack(res['message'] ?? 'Login failed', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: _blue,
        resizeToAvoidBottomInset: true,
        body: Theme(
          data: ThemeData.light().copyWith(textTheme: GoogleFonts.poppinsTextTheme()),
          child: Stack(children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_blue, Color(0xFF1565D8), Colors.white], stops: [0.0, 0.42, 0.42]),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: size.height * 0.42,
              child: FadeTransition(
                opacity: _logoFade,
                child: SafeArea(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    JT.brandBadge(
                      dark: true,
                      logoHeight: 26,
                      padding: 12,
                      radius: 20,
                    ),
                    const SizedBox(height: 12),
                    Text('Earn. Drive. Grow.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.white.withValues(alpha: 0.75), letterSpacing: 0.5)),
                  ]),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _cardSlide,
                child: Container(
                  constraints: BoxConstraints(maxHeight: size.height * 0.64),
                  decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(left: 28, right: 28, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 32),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Center(child: Container(margin: const EdgeInsets.only(top: 12, bottom: 20), width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)))),
                      Text('Welcome Back', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w500, color: _dark)),
                      const SizedBox(height: 4),
                      Text('Login with mobile number and password', style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF94A3B8))),
                      const SizedBox(height: 24),
                      _buildPhoneField(),
                      const SizedBox(height: 14),
                      _buildPasswordField(),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                          child: Text('Forgot Password?', style: GoogleFonts.poppins(color: _blue, fontWeight: FontWeight.w400, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildButton('Login', _loginWithPassword),
                      const SizedBox(height: 28),
                      Row(children: [
                        const Expanded(child: Divider(color: Color(0xFFF1F5F9), thickness: 1.5)),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Text('or', style: GoogleFonts.poppins(color: const Color(0xFFCBD5E1), fontSize: 13))),
                        const Expanded(child: Divider(color: Color(0xFFF1F5F9), thickness: 1.5)),
                      ]),
                      const SizedBox(height: 20),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text("New pilot?  ", style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 14)),
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                          child: Text('Register Now', style: GoogleFonts.poppins(color: _blue, fontWeight: FontWeight.w400, fontSize: 14)),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildPhoneField() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _blue.withValues(alpha: 0.3), width: 1.5)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(color: _blue.withValues(alpha: 0.08), borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)), border: Border(right: BorderSide(color: _blue.withValues(alpha: 0.2), width: 1.5))),
          child: Text('+91', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w400, color: _blue)),
        ),
        Expanded(
          child: TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w400, color: _dark),
            decoration: InputDecoration(hintText: 'Mobile number', hintStyle: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFFCBD5E1)), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18)),
          ),
        ),
      ]),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5)),
      child: TextField(
        controller: _passwordCtrl,
        obscureText: !_showPassword,
        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w400, color: _dark),
        decoration: InputDecoration(
          hintText: 'Password',
          hintStyle: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFFCBD5E1)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFFCBD5E1), size: 20),
          suffixIcon: IconButton(icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: const Color(0xFFCBD5E1), size: 20), onPressed: () => setState(() => _showPassword = !_showPassword)),
        ),
        onSubmitted: (_) => _loginWithPassword(),
      ),
    );
  }

  Widget _buildButton(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: _loading ? null : onTap,
        style: ElevatedButton.styleFrom(backgroundColor: _loading ? _blue.withValues(alpha: 0.4) : _blue, foregroundColor: Colors.white, elevation: _loading ? 0 : 6, shadowColor: _blue.withValues(alpha: 0.4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        child: _loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Text(label, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w400, color: Colors.white, letterSpacing: 0.3)),
      ),
    );
  }
}
