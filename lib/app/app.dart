import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';
import '../screens/home_screen.dart';
import '../screens/history_screen.dart';
import '../screens/contacts_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/login_screen.dart';
import '../services/check_in_service.dart';
import '../services/check_in_config_service.dart';
import '../models/check_in_config.dart';
import '../services/home_widget_service.dart';
import '../services/notification_service.dart';
import '../widgets/offline_sync_banner.dart';
import '../screens/trusted_contact_dashboard_screen.dart';

class SinhTuApp extends StatelessWidget {
  const SinhTuApp({super.key});

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF078D83);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sinh Tử',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF2F7F8),
        colorScheme: ColorScheme.fromSeed(seedColor: teal),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF082F49),
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// Cổng kiểm tra xác thực (AuthGate):
/// - Chưa đăng nhập: Mở màn hình LoginScreen
/// - Đã đăng nhập: Chuyển thẳng vào giao diện MainNavigation của Sinh Tử
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        // Đang kiểm tra token / trạng thái đăng nhập
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF2F7F8),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF078D83)),
            ),
          );
        }

        // Đã xác thực thành công
        if (snapshot.hasData && snapshot.data != null) {
          return const MainNavigation();
        }

        // Chưa đăng nhập -> Vào màn hình Login
        return const LoginScreen();
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int selectedIndex = 0;
  DateTime? lastCheckIn;
  CheckInConfig? _config;
  Timer? _refreshTimer;

  final _checkInService = CheckInService.instance;
  final _configService = CheckInConfigService.instance;

  @override
  void initState() {
    super.initState();
    quickCheckInConfirmationRequested.addListener(
      _handleQuickCheckInConfirmation,
    );
    _initCheckInData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleQuickCheckInConfirmation();
    });
    // Khởi tạo timer cập nhật đếm ngược mỗi 30 giây để đồng hồ luôn chính xác
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    quickCheckInConfirmationRequested.removeListener(
      _handleQuickCheckInConfirmation,
    );
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _handleQuickCheckInConfirmation() {
    if (!quickCheckInConfirmationRequested.value || !mounted) return;
    quickCheckInConfirmationRequested.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Xác nhận an toàn'),
          content: const Text(
            'Bạn có chắc muốn xác nhận bạn vẫn an toàn ngay bây giờ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Chưa chắc'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Tôi vẫn an toàn'),
            ),
          ],
        ),
      );
      if (confirmed == true) await checkIn();
    });
  }

  Future<void> _initCheckInData() async {
    try {
      final config = await _configService.getConfig();
      final latest =
          config.lastCheckInAt ?? await _checkInService.getLatestCheckInTime();

      if (mounted) {
        setState(() {
          _config = config;
          if (latest != null) lastCheckIn = latest;
        });
      }
      // Tự động đồng bộ các bản ghi offline chờ sẵn trong nền khi app mở
      _checkInService.syncPendingCheckIns();
    } catch (_) {
      // Bỏ qua lỗi ngầm khi khởi động để không ảnh hưởng app
    }
  }

  Future<void> checkIn() async {
    final result = await _checkInService.recordCheckIn();
    final updatedConfig = await _configService.getConfig();

    if (mounted) {
      setState(() {
        lastCheckIn = result.checkIn.checkedInAt;
        _config = updatedConfig;
      });
      await HomeWidgetService.instance.saveAndUpdate(
        result.checkIn.checkedInAt,
        updatedConfig,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Đã ghi nhận xác nhận an toàn!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: result.isSynced
              ? const Color(0xFF078D83)
              : const Color(0xFF082F49),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        lastCheckIn: lastCheckIn,
        config: _config,
        onCheckIn: checkIn,
        onOpenContacts: () {
          setState(() => selectedIndex = 2);
        },
      ),
      const HistoryScreen(),
      const ContactsScreen(),
      const TrustedContactDashboardScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: selectedIndex, children: pages),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OfflineSyncBanner(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() => selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            label: 'Lịch sử',
          ),
          NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            label: 'Danh bạ',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group_rounded),
            label: 'Người thân',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Cài đặt',
          ),
        ],
      ),
    );
  }
}
