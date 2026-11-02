class Validators {
  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );

  /// Kiểm tra họ tên
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Vui lòng nhập họ và tên của bạn';
    }
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      return 'Họ và tên phải có ít nhất 2 ký tự';
    }
    if (RegExp(r'[0-9]').hasMatch(trimmed)) {
      return 'Họ và tên không nên chứa chữ số';
    }
    return null;
  }

  /// Kiểm tra địa chỉ Email
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Vui lòng nhập địa chỉ email';
    }
    final trimmed = value.trim();
    if (!trimmed.contains('@')) {
      return 'Email phải chứa ký tự "@"';
    }
    if (!_emailRegExp.hasMatch(trimmed)) {
      return 'Định dạng email không hợp lệ (ví dụ: ten@gmail.com)';
    }
    return null;
  }

  /// Kiểm tra Mật khẩu khi đăng nhập
  static String? validateLoginPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập mật khẩu';
    }
    if (value.length < 6) {
      return 'Mật khẩu phải có ít nhất 6 ký tự';
    }
    return null;
  }

  /// Kiểm tra Mật khẩu khi đăng ký (yêu cầu chặt chẽ hơn)
  static String? validateRegisterPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng tạo mật khẩu';
    }
    if (value.length < 6) {
      return 'Mật khẩu tối thiểu 6 ký tự';
    }
    if (!RegExp(r'[a-zA-Z]').hasMatch(value)) {
      return 'Mật khẩu phải có ít nhất 1 chữ cái';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Mật khẩu phải có ít nhất 1 chữ số';
    }
    return null;
  }

  /// Kiểm tra Mật khẩu xác nhận
  static String? validateConfirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập lại mật khẩu để xác nhận';
    }
    if (value != password) {
      return 'Mật khẩu xác nhận không trùng khớp';
    }
    return null;
  }

  /// Tính điểm độ mạnh của mật khẩu từ 0.0 đến 1.0
  static double getPasswordStrength(String password) {
    if (password.isEmpty) return 0.0;
    double strength = 0.0;

    // Chiều dài
    if (password.length >= 6) strength += 0.25;
    if (password.length >= 8) strength += 0.25;

    // Chứa chữ hoa và chữ thường
    if (RegExp(r'(?=.*[a-z])(?=.*[A-Z])').hasMatch(password)) {
      strength += 0.25;
    }

    // Chứa số hoặc ký tự đặc biệt
    if (RegExp(r'[0-9]').hasMatch(password) &&
        RegExp(r'[!@#\$&*~]').hasMatch(password)) {
      strength += 0.25;
    } else if (RegExp(r'[0-9]').hasMatch(password) ||
        RegExp(r'[!@#\$&*~]').hasMatch(password)) {
      strength += 0.15;
    }

    return strength.clamp(0.0, 1.0);
  }

  /// Nhãn hiển thị độ mạnh mật khẩu
  static String getPasswordStrengthLabel(double strength) {
    if (strength <= 0.0) return '';
    if (strength <= 0.35) return 'Mật khẩu yếu';
    if (strength <= 0.7) return 'Mật khẩu trung bình';
    return 'Mật khẩu rất mạnh';
  }
}
