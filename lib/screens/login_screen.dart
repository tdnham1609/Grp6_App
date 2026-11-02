import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../utils/validators.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _authService = AuthService();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _hasAttemptedSubmit = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() => _hasAttemptedSubmit = true);
    if (!_formKey.currentState!.validate()) return;

    // Ẩn bàn phím
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      await _authService.signInWithEmailPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
      // Khi thành công, AuthGate sẽ tự động chuyển vào HomeScreen
    } catch (e) {
      if (!mounted) return;
      _showCustomSnackBar(message: e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final credential = await _authService.signInWithGoogle();
      if (credential == null) return;
    } catch (e) {
      if (!mounted) return;
      _showCustomSnackBar(message: e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _showCustomSnackBar({required String message, bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError
            ? const Color(0xFFE53935)
            : const Color(0xFF00897B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  void _showForgotPasswordBottomSheet() {
    final resetController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final sheetFormKey = GlobalKey<FormState>();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Form(
                key: sheetFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Row(
                      children: [
                        Icon(
                          Icons.lock_reset_rounded,
                          color: Color(0xFF078D83),
                          size: 28,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Quên mật khẩu?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF062C43),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nhập địa chỉ email đã đăng ký. Hệ thống sẽ gửi cho bạn một liên kết an toàn để đặt lại mật khẩu mới.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: const Color(0xFF062C43).withValues(alpha: 0.7),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: resetController,
                      keyboardType: TextInputType.emailAddress,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: InputDecoration(
                        labelText: 'Email tài khoản',
                        hintText: 'ten@gmail.com',
                        prefixIcon: const Icon(
                          Icons.mail_outline_rounded,
                          color: Color(0xFF078D83),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFF078D83),
                            width: 2,
                          ),
                        ),
                      ),
                      validator: Validators.validateEmail,
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF078D83),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: isSending
                            ? null
                            : () async {
                                if (!sheetFormKey.currentState!.validate()) {
                                  return;
                                }
                                setSheetState(() => isSending = true);
                                try {
                                  await _authService.sendPasswordResetEmail(
                                    resetController.text.trim(),
                                  );
                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                  _showCustomSnackBar(
                                    message: 'Đã gửi liên kết khôi phục tới email của bạn. Vui lòng kiểm tra hộp thư.',
                                  );
                                } catch (e) {
                                  setSheetState(() => isSending = false);
                                  if (!mounted) return;
                                  _showCustomSnackBar(
                                    message: e.toString(),
                                    isError: true,
                                  );
                                }
                              },
                        child: isSending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'GỬI LIÊN KẾT ĐẶT LẠI MẬT KHẨU',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF062C43);
    const teal = Color(0xFF078D83);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F6F8),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Hero Banner vát cong cao cấp
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF041C2C),
                    Color(0xFF062C43),
                    Color(0xFF075B65),
                    Color(0xFF078D83),
                  ],
                  stops: [0.0, 0.35, 0.7, 1.0],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(38),
                  bottomRight: Radius.circular(38),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Icon Khiên phát sáng ánh ngọc
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFF50E3C2), Color(0xFF078D83)],
                        radius: 0.85,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF50E3C2)
                              .withValues(alpha: 0.45),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.shield_moon_rounded,
                      color: Color(0xFF041C2C),
                      size: 46,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'SINH TỬ',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Hệ thống xác nhận an toàn chủ động',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFBBE5E3),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Form container chính
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF075B65).withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  autovalidateMode: _hasAttemptedSubmit
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Đăng nhập tài khoản',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Nhập thông tin bên dưới để tiếp tục',
                        style: TextStyle(
                          fontSize: 13,
                          color: navy.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Trường Email
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'ten@gmail.com',
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: teal.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.mail_outline_rounded,
                                color: teal,
                                size: 20,
                              ),
                            ),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(color: teal, width: 2),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFFE53935),
                              width: 1.5,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFFE53935),
                              width: 2,
                            ),
                          ),
                        ),
                        validator: Validators.validateEmail,
                      ),
                      const SizedBox(height: 18),

                      // Trường Mật khẩu
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleLogin(),
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu',
                          hintText: 'Tối thiểu 6 ký tự',
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: teal.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.lock_outline_rounded,
                                color: teal,
                                size: 20,
                              ),
                            ),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0xFF64748B),
                            ),
                            onPressed: () {
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(color: teal, width: 2),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFFE53935),
                              width: 1.5,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFFE53935),
                              width: 2,
                            ),
                          ),
                        ),
                        validator: Validators.validateLoginPassword,
                      ),

                      // Quên mật khẩu
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showForgotPasswordBottomSheet,
                          style: TextButton.styleFrom(
                            foregroundColor: teal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                          ),
                          child: const Text(
                            'Quên mật khẩu?',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Nút ĐĂNG NHẬP (Gradient Button)
                      SizedBox(
                        height: 56,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF12CBB0), Color(0xFF008D83)],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: teal.withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'ĐĂNG NHẬP',
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Divider "Hoặc"
                      Row(
                        children: [
                          const Expanded(
                            child: Divider(
                              color: Color(0xFFE2E8F0),
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              'Hoặc tiếp tục với',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: navy.withValues(alpha: 0.55),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Divider(
                              color: Color(0xFFE2E8F0),
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Nút Đăng nhập bằng Google
                      SizedBox(
                        height: 54,
                        child: OutlinedButton(
                          onPressed: _isGoogleLoading
                              ? null
                              : _handleGoogleSignIn,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: navy,
                            side: const BorderSide(
                              color: Color(0xFFCBD5E1),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _isGoogleLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: teal,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                      ),
                                      child: Image.network(
                                        'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Icon(
                                                  Icons.g_mobiledata_rounded,
                                                  color: Color(0xFFEA4335),
                                                  size: 28,
                                                ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Đăng nhập với Google',
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Điều hướng Đăng ký
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Chưa có tài khoản? ',
                            style: TextStyle(
                              color: navy.withValues(alpha: 0.7),
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            key: const Key('register_button'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Đăng ký ngay',
                              style: TextStyle(
                                color: teal,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
