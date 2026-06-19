import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/jago_theme.dart';
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import '../main_screen.dart';
import 'register_screen.dart';

class OtpVerifyScreen extends StatefulWidget {
  final String phone;
  final String? devOtp;
  const OtpVerifyScreen({super.key, required this.phone, this.devOtp});
  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final List<TextEditingController> _ctrls = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  int _resendSeconds = 30;
  late final _timer = Stream.periodic(const Duration(seconds: 1));

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    if (widget.devOtp != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Dev OTP: ${widget.devOtp}', style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: JT.success,
          duration: const Duration(seconds: 5),
        ));
      });
    }
  }

  void _startResendTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() { if (_resendSeconds > 0) _resendSeconds--; });
      return _resendSeconds > 0;
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    for (final n in _nodes) n.dispose();
    super.dispose();
  }

  String get _otp => _ctrls.map((c) => c.text).join();

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
      backgroundColor: error ? JT.error : JT.success,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _verify() async {
    if (_otp.length != 6) { _snack('6 digit OTP enter cheyyi', error: true); return; }
    setState(() => _loading = true);
    final res = await AuthService.verifyOtp(widget.phone, _otp);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true || res['token'] != null) {
      if (res['isNewUser'] == true) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
      } else {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainScreen()), (_) => false);
      }
    } else {
      _snack(res['message'] ?? 'Invalid OTP', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF111827)), onPressed: () => Navigator.pop(context)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            Text('Verify OTP', style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
            const SizedBox(height: 8),
            RichText(text: TextSpan(
              style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF6B7280)),
              children: [
                const TextSpan(text: 'OTP sent to +91 '),
                TextSpan(text: widget.phone, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827))),
              ],
            )),
            const SizedBox(height: 40),

            // 6 OTP boxes
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(6, (i) => _otpBox(i))),

            const SizedBox(height: 32),

            // Verify button
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _verify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E6FE8), foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : Text('Verify & Continue', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),

            const SizedBox(height: 24),

            // Resend
            Center(child: _resendSeconds > 0
                ? Text('Resend OTP in ${_resendSeconds}s', style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF9CA3AF)))
                : GestureDetector(
                    onTap: () { setState(() => _resendSeconds = 30); _startResendTimer(); },
                    child: Text('Resend OTP', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E6FE8))),
                  )),
          ]),
        ),
      ),
    );
  }

  Widget _otpBox(int i) {
    return SizedBox(
      width: 48, height: 56,
      child: TextField(
        controller: _ctrls[i],
        focusNode: _nodes[i],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)],
        style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF111827)),
        decoration: InputDecoration(
          counterText: '',
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDDE6F5), width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E6FE8), width: 2)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDDE6F5), width: 1.5)),
        ),
        onChanged: (v) {
          if (v.isNotEmpty && i < 5) FocusScope.of(context).requestFocus(_nodes[i + 1]);
          if (v.isEmpty && i > 0) FocusScope.of(context).requestFocus(_nodes[i - 1]);
          if (i == 5 && v.isNotEmpty) _verify();
        },
      ),
    );
  }
}
