import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/jago_theme.dart';
import '../../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w400)),
      backgroundColor: error ? const Color(0xFFE53935) : JT.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _requestReset() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 10) {
      _showSnack('Enter a valid 10-digit phone number', error: true);
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    final res = await AuthService.forgotPassword(phone);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _message = res['message']?.toString() ?? 'Password reset request received.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A2E)), onPressed: () => Navigator.pop(context)),
          title: const Text('Forgot Password', style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w500)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lock_reset_rounded, size: 56, color: JT.primary),
            const SizedBox(height: 16),
            Text('Reset Your Password', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w400, color: Colors.grey[900])),
            const SizedBox(height: 8),
            Text('Enter your registered mobile number. Support will verify ownership and help reset your password securely.', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
            const SizedBox(height: 32),
            Text('Phone Number', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[700])),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('+91', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                Container(width: 1, height: 24, color: Colors.grey[300]),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
                    decoration: const InputDecoration(hintText: 'Enter 10-digit number', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
                  ),
                ),
              ]),
            ),
            if (_message != null) ...[
              const SizedBox(height: 18),
              Text(_message!, style: const TextStyle(color: Color(0xFF475569), fontSize: 14)),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _loading ? null : _requestReset,
                style: ElevatedButton.styleFrom(backgroundColor: JT.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                child: _loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)) : const Text('Request Password Reset', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
