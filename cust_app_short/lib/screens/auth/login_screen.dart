import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/jago_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth/login/login_background.dart';
import '../../widgets/auth/login/login_card.dart';
import '../../widgets/auth/login/login_create_account_tile.dart';
import '../../widgets/auth/login/login_feature_highlights.dart';
import '../../widgets/auth/login/login_header.dart';
import '../../widgets/auth/login/login_mode_switcher.dart';
import '../../widgets/auth/login/login_or_divider.dart';
import '../../widgets/auth/login/login_password_field.dart';
import '../../widgets/auth/login/login_phone_field.dart';
import '../../widgets/auth/login/login_primary_button.dart';
import '../../widgets/auth/login/login_security_banner.dart';
import '../main_screen.dart';
import 'forgot_password_screen.dart';
import 'otp_verify_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _showPassword = false;
  bool _loading = false;
  LoginMode _mode = LoginMode.phonePassword;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: JT.animationSlow,
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
      backgroundColor: error ? JT.error : JT.success,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(JT.spacing16, 0, JT.spacing16, JT.spacing16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JT.radiusMd)),
    ));
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 10) {
      _snack('Valid 10-digit mobile number enter cheyyi', error: true);
      return;
    }
    setState(() => _loading = true);
    final res = await AuthService.sendOtp(phone);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true || res['otp'] != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => OtpVerifyScreen(phone: phone, devOtp: res['otp']?.toString()),
      ));
    } else {
      _snack(res['message'] ?? 'OTP send chesadam failed', error: true);
    }
  }

  Future<void> _loginWithPhone() async {
    final phone = _phoneCtrl.text.trim();
    final pass = _passwordCtrl.text;
    if (phone.length != 10) {
      _snack('Valid 10-digit number enter cheyyi', error: true);
      return;
    }
    if (pass.length < 6) {
      _snack('Password minimum 6 characters undali', error: true);
      return;
    }
    setState(() => _loading = true);
    final res = await AuthService.loginWithPassword(phone, pass);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true || res['token'] != null) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (_) => false,
      );
    } else {
      _snack(res['message'] ?? 'Login failed. Check your credentials.', error: true);
    }
  }

  void _onContinue() {
    FocusScope.of(context).unfocus();
    if (_mode == LoginMode.otp) {
      _sendOtp();
    } else {
      _loginWithPhone();
    }
  }

  void _onPhoneSubmit() {
    if (_mode == LoginMode.phonePassword) {
      _passwordFocus.requestFocus();
    } else {
      _onContinue();
    }
  }

  void _onModeChanged(LoginMode mode) {
    FocusScope.of(context).unfocus();
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isPasswordMode = _mode == LoginMode.phonePassword;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: FadeTransition(
        opacity: _fade,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const LoginBackground(),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LoginHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        JT.spacing16,
                        JT.spacing8,
                        JT.spacing16,
                        bottomInset > 0 ? JT.spacing12 : 0,
                      ),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      child: LoginCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LoginModeSwitcher(
                              mode: _mode,
                              onModeChanged: _onModeChanged,
                            ),
                            const SizedBox(height: JT.spacing16),
                            LoginSecurityBanner(mode: _mode),
                            const SizedBox(height: JT.spacing16),
                            LoginPhoneField(
                              controller: _phoneCtrl,
                              focusNode: _phoneFocus,
                              moveToPasswordOnSubmit: isPasswordMode,
                              onDone: _onPhoneSubmit,
                            ),
                            if (isPasswordMode) ...[
                              const SizedBox(height: JT.spacing16),
                              LoginPasswordField(
                                controller: _passwordCtrl,
                                focusNode: _passwordFocus,
                                showPassword: _showPassword,
                                onToggleVisibility: () {
                                  setState(() => _showPassword = !_showPassword);
                                },
                                onSubmit: _onContinue,
                              ),
                              const SizedBox(height: JT.spacing8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ForgotPasswordScreen(),
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: JT.primary,
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Forgot Password?',
                                    style: JT.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: JT.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: JT.spacing12),
                              Row(
                                children: [
                                  Icon(
                                    Icons.sms_outlined,
                                    size: 14,
                                    color: JT.primary.withValues(alpha: 0.8),
                                  ),
                                  const SizedBox(width: JT.spacing8),
                                  Text(
                                    '6-digit OTP will be sent to this number',
                                    style: JT.caption,
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: JT.spacing24),
                            LoginPrimaryButton(
                              label: isPasswordMode ? 'Login' : 'Send OTP',
                              loading: _loading,
                              onPressed: _onContinue,
                            ),
                            const SizedBox(height: JT.spacing16),
                            const LoginOrDivider(),
                            const SizedBox(height: JT.spacing16),
                            LoginCreateAccountTile(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const RegisterScreen()),
                              ),
                            ),
                            const SizedBox(height: JT.spacing24),
                            const LoginFeatureHighlights(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: JT.spacing16),
                    child: Text(
                      'v 1.0.62',
                      textAlign: TextAlign.center,
                      style: JT.caption.copyWith(color: JT.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
