import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/check_in.dart';
import '../services/check_in_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _checkInService = CheckInService.instance;
  final _dateFormat = DateFormat('HH:mm:ss  •  dd/MM/yyyy');
  final _dayFormat = DateFormat('dd/MM/yyyy');
  final _timeFormat = DateFormat('HH:mm:ss');

  List<CheckIn> _history = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await _checkInService.getCheckInHistory();
      if (mounted) {
        setState(() {
          _history = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Không thể tải lịch sử: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSyncNow() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    try {
      final count = await _checkInService.syncPendingCheckIns();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count > 0
                  ? 'Đã đồng bộ thành công $count bản ghi lên đám mây!'
                  : 'Tất cả bản ghi an toàn đã được đồng bộ.',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF078D83),
          ),
        );
      }
      await _loadHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi đồng bộ: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryTeal = Color(0xFF078D83);
    const deepOcean = Color(0xFF082F49);

    final pendingCount = _history
        .where((c) => c.syncStatus == SyncStatus.pending)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F8),
      appBar: AppBar(
        title: const Text(
          'Lịch sử an toàn',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: deepOcean,
        foregroundColor: Colors.white,
        actions: [
          if (pendingCount > 0)
            IconButton(
              tooltip: 'Đồng bộ bản ghi chờ',
              onPressed: _isSyncing ? null : _handleSyncNow,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Badge(
                      label: Text('!'),
                      child: Icon(Icons.cloud_upload_rounded),
                    ),
            ),
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _buildBody(primaryTeal, deepOcean, pendingCount),
    );
  }

  Widget _buildBody(Color primaryTeal, Color deepOcean, int pendingCount) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF078D83)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF52717D), fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadHistory,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Thử lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryTeal,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_history.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadHistory,
        color: primaryTeal,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
          children: [
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryTeal.withValues(alpha: 0.1),
                ),
                child: const Icon(
                  Icons.history_toggle_off_rounded,
                  size: 50,
                  color: Color(0xFF078D83),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Chưa có lịch sử xác nhận',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF082F49),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Mỗi lần bạn bấm "TÔI VẪN AN TOÀN" trên trang chủ, '
              'thời điểm xác nhận sẽ được ghi nhận và hiển thị tại đây.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6B8793),
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: primaryTeal,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _history.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildHeaderSummary(primaryTeal, deepOcean, pendingCount);
          }
          final item = _history[index - 1];
          return _buildCheckInCard(item, primaryTeal, deepOcean);
        },
      ),
    );
  }

  Widget _buildHeaderSummary(
    Color primaryTeal,
    Color deepOcean,
    int pendingCount,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [deepOcean, const Color(0xFF0A4060)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: deepOcean.withValues(alpha: 0.15),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TỔNG SỐ LẦN ĐIỂM DANH',
                style: TextStyle(
                  color: Color(0xFF90C0D4),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: pendingCount > 0
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                      : const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      pendingCount > 0
                          ? Icons.cloud_queue_rounded
                          : Icons.cloud_done_rounded,
                      size: 14,
                      color: pendingCount > 0
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF34D399),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      pendingCount > 0
                          ? '$pendingCount chờ đồng bộ'
                          : 'Đã đồng bộ đám mây',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: pendingCount > 0
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFF34D399),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_history.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Gần nhất: ${_dateFormat.format(_history.first.checkedInAt)}',
            style: const TextStyle(color: Color(0xFFC7EAE7), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInCard(CheckIn item, Color primaryTeal, Color deepOcean) {
    final isSynced = item.isSynced;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSynced
              ? const Color(0xFFE2EBF0)
              : const Color(0xFFFDE68A), // vàng nhạt nếu pending
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isSynced
                  ? const Color(0xFFE0F7F2)
                  : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isSynced ? Icons.verified_rounded : Icons.pending_rounded,
              color: isSynced ? primaryTeal : const Color(0xFFD97706),
              size: 24,
            ),
          ),
          title: Text(
            _timeFormat.format(item.checkedInAt),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF082F49),
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _dayFormat.format(item.checkedInAt),
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B8793)),
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: isSynced
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSynced
                    ? const Color(0xFFA7F3D0)
                    : const Color(0xFFFDE68A),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSynced
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_upload_outlined,
                  size: 14,
                  color: isSynced
                      ? const Color(0xFF059669)
                      : const Color(0xFFD97706),
                ),
                const SizedBox(width: 4),
                Text(
                  isSynced ? 'Đã lưu mây' : 'Chờ mạng',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSynced
                        ? const Color(0xFF059669)
                        : const Color(0xFFD97706),
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
