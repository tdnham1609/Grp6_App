import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../utils/validators.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _authService = AuthService();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _hasAttemptedSubmit = false;

  double _passwordStrength = 0.0;
  String _passwordStrengthLabel = '';

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_updatePasswordStrength);
  }

  void _updatePasswordStrength() {
    final text = _passwordController.text;
    final strength = Validators.getPasswordStrength(text);
    setState(() {
      _passwordStrength = strength;
      _passwordStrengthLabel = Validators.getPasswordStrengthLabel(strength);
    });
  }

  @override
  void dispose() {
    _passwordController.removeListener(_updatePasswordStrength);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    setState(() => _hasAttemptedSubmit = true);
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      await _authService.registerWithEmailPassword(
        email: _emailController.text,
        password: _passwordController.text,
        displayName: _nameController.text,
      );

      if (!mounted) return;
      _showCustomSnackBar(
        message: 'Tạo tài khoản thành công! Đang chuyển hướng...',
      );

      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
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
      if (credential != null && mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
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

  Color _getStrengthColor() {
    if (_passwordStrength <= 0.35) return const Color(0xFFE53935);
    if (_passwordStrength <= 0.7) return const Color(0xFFFFA000);
    return const Color(0xFF00897B);
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF062C43);
    const teal = Color(0xFF078D83);

    final password = _passwordController.text;
    final hasLength = password.length >= 6;
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F6F8),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Hero Banner vát cong cao cấp
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 36),
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
                  // Nút Back
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Icon Khiên phát sáng
                  Container(
                    width: 76,
                    height: 76,
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
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.shield_moon_rounded,
                      color: Color(0xFF041C2C),
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'TẠO TÀI KHOẢN',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 2.5,
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
                      'Bảo vệ bản thân và những người bạn thương yêu',
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
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
                        'Thông tin cá nhân',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Điền đầy đủ các mục để kích hoạt bảo vệ an toàn',
                        style: TextStyle(
                          fontSize: 13,
                          color: navy.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Trường Họ và tên
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Họ và tên',
                          hintText: 'Nguyễn Văn A',
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: teal.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.person_outline_rounded,
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
                        validator: Validators.validateName,
                      ),
                      const SizedBox(height: 16),

                      // Trường Email
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Địa chỉ Email',
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
                      const SizedBox(height: 16),

                      // Trường Mật khẩu
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu',
                          hintText: 'Ít nhất 6 ký tự gồm chữ & số',
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
                        validator: Validators.validateRegisterPassword,
                      ),

                      // Thanh đo độ mạnh mật khẩu (Password Strength Meter)
                      if (_passwordController.text.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: _passwordStrength,
                                  backgroundColor: const Color(0xFFE2E8F0),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _getStrengthColor(),
                                  ),
                                  minHeight: 6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _passwordStrengthLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _getStrengthColor(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Checklist yêu cầu mật khẩu thời gian thực
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _buildRequirementTag(
                              'Tối thiểu 6 ký tự',
                              hasLength,
                            ),
                            _buildRequirementTag('Có chữ cái', hasLetter),
                            _buildRequirementTag('Có chữ số', hasNumber),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Trường Xác nhận mật khẩu
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleRegister(),
                        decoration: InputDecoration(
                          labelText: 'Xác nhận mật khẩu',
                          hintText: 'Nhập lại chính xác mật khẩu trên',
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: teal.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.lock_reset_rounded,
                                color: teal,
                                size: 20,
                              ),
                            ),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0xFF64748B),
                            ),
                            onPressed: () {
                              setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
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
                        validator: (value) =>
                            Validators.validateConfirmPassword(
                              value,
                              _passwordController.text,
                            ),
                      ),
                      const SizedBox(height: 24),

                      // Nút ĐĂNG KÝ (Gradient Button)
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
                            onPressed: _isLoading ? null : _handleRegister,
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
                                        'TẠO TÀI KHOẢN',
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(
                                        Icons.check_circle_rounded,
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
                              'Hoặc đăng ký nhanh',
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

                      // Nút Đăng ký bằng Google
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
                                      'Đăng ký với Google',
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

                      // Điều hướng Đăng nhập
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Đã có tài khoản? ',
                            style: TextStyle(
                              color: navy.withValues(alpha: 0.7),
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            key: const Key('login_link_button'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Đăng nhập ngay',
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

  Widget _buildRequirementTag(String text, bool isMet) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isMet
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 14,
          color: isMet ? const Color(0xFF00897B) : const Color(0xFF94A3B8),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isMet ? FontWeight.bold : FontWeight.normal,
            color: isMet ? const Color(0xFF00897B) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
