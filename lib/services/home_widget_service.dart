import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../firebase_options.dart';
import '../models/check_in_config.dart';
import 'check_in_service.dart';
import 'check_in_config_service.dart';

const String _androidWidgetName =
    'com.example.deadmansswitch.SinhTuWidgetProvider';
const String _widgetCheckInUri = 'sinhtu://widget/checkin';

@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  if (uri?.toString() != _widgetCheckInUri) return;

  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    if (Firebase.apps.isEmpty) rethrow;
  }

  final result = await CheckInService.instance.recordCheckIn();
  await HomeWidgetService.instance.updateStatusFromConfig();
  await HomeWidgetService.instance.saveAndUpdate(
    result.checkIn.checkedInAt,
    null,
  );
}

class HomeWidgetService {
  HomeWidgetService._();

  static final HomeWidgetService instance = HomeWidgetService._();

  Future<void> initialize() async {
    if (!kIsWeb && Platform.isAndroid) {
      HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback);
      try {
        await updateStatusFromConfig();
      } catch (error) {
        debugPrint('Home widget startup update failed: $error');
      }
    }
  }

  Future<void> updateStatusFromConfig() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final config = await CheckInConfigService.instance.getConfig();
      await saveAndUpdate(config.lastCheckInAt, config);
    } catch (_) {
      await saveAndUpdate(null, null);
    }
  }

  Future<void> saveAndUpdate(
    DateTime? checkedInAt,
    CheckInConfig? config,
  ) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final status = config?.getRemainingFormatted() ?? 'Chưa có lịch xác nhận';
    final lastCheckIn = checkedInAt == null
        ? (config?.lastCheckInAt == null
              ? ''
              : 'Lần cuối: ${_formatDate(config!.lastCheckInAt!)}')
        : 'Lần cuối: ${_formatDate(checkedInAt)}';

    await HomeWidget.saveWidgetData<String>('widget_status', status);
    await HomeWidget.saveWidgetData<String>('widget_last_checkin', lastCheckIn);
    await HomeWidget.updateWidget(name: _androidWidgetName);
  }

  String _formatDate(DateTime value) => _formatWidgetDate(value);
}

String _formatWidgetDate(DateTime value) {
  final local = value.toLocal();
  return '${_padTwo(local.hour)}:${_padTwo(local.minute)} '
      '${_padTwo(local.day)}/${_padTwo(local.month)}';
}

String _padTwo(int number) => number.toString().padLeft(2, '0');
