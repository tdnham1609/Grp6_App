import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../models/check_in.dart';
import '../services/check_in_service.dart';

class OfflineSyncBanner extends StatefulWidget {
  const OfflineSyncBanner({super.key});

  @override
  State<OfflineSyncBanner> createState() => _OfflineSyncBannerState();
}

class _OfflineSyncBannerState extends State<OfflineSyncBanner> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOffline = false;
  int _pendingCount = 0;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _refreshConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (_) => _refreshConnectivity(),
    );
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    final offline = results.every(
      (result) => result == ConnectivityResult.none,
    );

    int pendingCount = 0;
    try {
      final history = await CheckInService.instance.getCheckInHistory();
      pendingCount = history
          .where((item) => item.syncStatus == SyncStatus.pending)
          .length;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isOffline = offline;
      _pendingCount = pendingCount;
    });

    if (!offline && pendingCount > 0) {
      await _syncPending();
    }
  }

  Future<void> _syncPending() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      await CheckInService.instance.syncPendingCheckIns();
      await _refreshConnectivity();
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOffline && _pendingCount == 0) return const SizedBox.shrink();

    return SafeArea(
      bottom: false,
      child: Material(
        color: _isOffline ? const Color(0xFFB54708) : const Color(0xFF078D83),
        child: InkWell(
          onTap: _isOffline || _isSyncing ? null : _syncPending,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isOffline
                      ? Icons.cloud_off_rounded
                      : Icons.cloud_sync_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _isOffline
                        ? 'Ngoại tuyến • $_pendingCount bản ghi đang chờ đồng bộ'
                        : _isSyncing
                            ? 'Đang đồng bộ $_pendingCount bản ghi…'
                            : 'Đã mạng trở lại • $_pendingCount bản ghi chờ đồng bộ',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
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
}
