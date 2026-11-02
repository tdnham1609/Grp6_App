import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import '../utils/validators.dart';

/// Màn hình hồ sơ người dùng — Sinh Tử
/// - Hiển thị thông tin từ Firestore (realtime stream)
/// - Cho phép chỉnh sửa họ tên
/// - Hiển thị ảnh đại diện hoặc avatar mặc định
/// - Có nút đăng xuất với xác nhận
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _navy = Color(0xFF062C43);
  static const Color _teal = Color(0xFF078D83);
  static const Color _darkBg = Color(0xFF041C2C);

  final _profileService = UserProfileService();
  final _authService = AuthService();

  // ─── Chỉnh sửa họ tên ────────────────────────────────────────────────────

  Future<void> _showEditNameDialog(
    BuildContext context,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.edit_rounded, color: _teal, size: 22),
              SizedBox(width: 10),
              Text(
                'Cập nhật họ tên',
                style: TextStyle(
                  color: _navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Họ và tên',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _teal, width: 2),
                ),
              ),
              validator: Validators.validateName,
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text(
                'Hủy',
                style: TextStyle(color: _navy.withValues(alpha: 0.6)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => isSaving = true);
                      try {
                        await _profileService.updateDisplayName(
                          controller.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          _showSnackBar('Đã cập nhật họ tên thành công!');
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          _showSnackBar(e.toString(), isError: true);
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Lưu',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Đăng xuất ───────────────────────────────────────────────────────────

  Future<void> _handleSignOut(BuildContext context) async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Đăng xuất'),
        content: const Text(
          'Bạn có chắc muốn đăng xuất khỏi ứng dụng Sinh Tử?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      await _authService.signOut();
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
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

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F6F8),
      body: StreamBuilder<UserProfile?>(
        stream: _profileService.streamCurrentUserProfile(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingView();
          }

          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: () => setState(() {}),
            );
          }

          final profile = snapshot.data;

          return CustomScrollView(
            slivers: [
              _buildSliverAppBar(context, profile),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 20),
                    if (profile != null) ...[
                      _buildInfoCard(context, profile),
                      const SizedBox(height: 16),
                      _buildAccountCard(profile),
                      const SizedBox(height: 24),
                    ] else
                      _buildNoProfileCard(),
                    _buildSignOutButton(context),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── SliverAppBar với avatar lớn ─────────────────────────────────────────

  Widget _buildSliverAppBar(BuildContext context, UserProfile? profile) {
    final photoUrl = profile?.photoUrl;
    final displayName = profile?.displayName ?? '';
    final initials = displayName.isNotEmpty
        ? displayName
              .trim()
              .split(' ')
              .map((w) => w.isNotEmpty ? w[0] : '')
              .take(2)
              .join()
              .toUpperCase()
        : (AuthService().currentUser?.email?.isNotEmpty == true
              ? AuthService().currentUser!.email![0].toUpperCase()
              : 'U');

    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      stretch: true,
      backgroundColor: _darkBg,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
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
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 32),
                // Avatar
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF50E3C2).withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                    border: Border.all(
                      color: const Color(0xFF50E3C2),
                      width: 3,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: _teal.withValues(alpha: 0.3),
                    backgroundImage: photoUrl != null
                        ? NetworkImage(photoUrl)
                        : null,
                    child: photoUrl == null
                        ? Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  displayName.isNotEmpty ? displayName : 'Người dùng Sinh Tử',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _getProviderLabel(profile?.provider),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFBBE5E3),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getProviderLabel(String? provider) {
    switch (provider) {
      case 'google':
        return '🔗 Đăng nhập qua Google';
      case 'password':
        return '🔑 Đăng nhập bằng Email';
      default:
        return '👤 Tài khoản Sinh Tử';
    }
  }

  // ─── Card thông tin cá nhân ───────────────────────────────────────────────

  Widget _buildInfoCard(BuildContext context, UserProfile profile) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded, color: _teal, size: 20),
              const SizedBox(width: 10),
              const Text(
                'Thông tin cá nhân',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showEditNameDialog(context, profile.displayName),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined, color: _teal, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Sửa',
                        style: TextStyle(
                          color: _teal,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.badge_rounded,
            label: 'Họ và tên',
            value: profile.displayName.isNotEmpty
                ? profile.displayName
                : 'Chưa cập nhật',
          ),
          const Divider(height: 20, color: Color(0xFFF0F4F8)),
          _InfoRow(
            icon: Icons.mail_outline_rounded,
            label: 'Email',
            value: profile.email.isNotEmpty ? profile.email : 'Chưa có email',
          ),
        ],
      ),
    );
  }

  // ─── Card thông tin tài khoản ─────────────────────────────────────────────

  Widget _buildAccountCard(UserProfile profile) {
    final dateStr = DateFormat('dd/MM/yyyy').format(profile.createdAt);
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_rounded, color: _teal, size: 20),
              SizedBox(width: 10),
              Text(
                'Thông tin tài khoản',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Ngày tạo tài khoản',
            value: dateStr,
          ),
          const Divider(height: 20, color: Color(0xFFF0F4F8)),
          _InfoRow(
            icon: Icons.fingerprint_rounded,
            label: 'UID',
            value: _truncateUid(profile.uid),
          ),
          const Divider(height: 20, color: Color(0xFFF0F4F8)),
          _InfoRow(
            icon: Icons.login_rounded,
            label: 'Phương thức đăng nhập',
            value: profile.provider == 'google' ? 'Google' : 'Email & Mật khẩu',
          ),
        ],
      ),
    );
  }

  String _truncateUid(String uid) {
    if (uid.length <= 12) return uid;
    return '${uid.substring(0, 6)}...${uid.substring(uid.length - 6)}';
  }

  // ─── Card khi chưa có hồ sơ ──────────────────────────────────────────────

  Widget _buildNoProfileCard() {
    return _SectionCard(
      child: Column(
        children: [
          const Icon(Icons.person_off_outlined, color: _teal, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Chưa tìm thấy hồ sơ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hồ sơ của bạn đang được đồng bộ hoặc chưa được tạo. Thử đăng xuất và đăng nhập lại.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _navy.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  // ─── Nút đăng xuất ────────────────────────────────────────────────────────

  Widget _buildSignOutButton(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () => _handleSignOut(context),
        icon: const Icon(Icons.logout_rounded, color: Color(0xFFD32F2F)),
        label: const Text(
          'Đăng xuất',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFFD32F2F),
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFFFCDD2)),
          backgroundColor: const Color(0xFFFFEBEE),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF078D83).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF078D83), size: 16),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: const Color(0xFF062C43).withValues(alpha: 0.55),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF062C43),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF1F6F8),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF078D83)),
            SizedBox(height: 16),
            Text(
              'Đang tải hồ sơ...',
              style: TextStyle(color: Color(0xFF062C43), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F6F8),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: Color(0xFF078D83),
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Không thể tải hồ sơ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF062C43),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: const Color(0xFF062C43).withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Thử lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF078D83),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
