import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/check_in_config.dart';

class StatusCard extends StatelessWidget {
  final DateTime? lastCheckIn;
  final CheckInConfig? config;

  const StatusCard({super.key, required this.lastCheckIn, this.config});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('HH:mm  •  dd/MM/yyyy');
    final status =
        config?.getStatus() ??
        (lastCheckIn != null ? CheckInStatus.onTime : CheckInStatus.noData);

    // Xác định màu sắc, biểu tượng và nhãn theo trạng thái
    final Color statusColor;
    final Color badgeBgColor;
    final IconData statusIcon;
    final String statusLabel;

    switch (status) {
      case CheckInStatus.onTime:
        statusColor = const Color(0xFF078D83);
        badgeBgColor = const Color(0xFFE0F7F2);
        statusIcon = Icons.check_circle_rounded;
        statusLabel = 'Đúng hạn (An toàn)';
        break;
      case CheckInStatus.dueSoon:
        statusColor = const Color(0xFFD97706);
        badgeBgColor = const Color(0xFFFEF3C7);
        statusIcon = Icons.alarm_rounded;
        statusLabel = 'Sắp đến hạn';
        break;
      case CheckInStatus.overdue:
        statusColor = const Color(0xFFDC2626);
        badgeBgColor = const Color(0xFFFEE2E2);
        statusIcon = Icons.warning_amber_rounded;
        statusLabel = 'Đã quá hạn';
        break;
      case CheckInStatus.noData:
        statusColor = const Color(0xFF52717D);
        badgeBgColor = const Color(0xFFE2EBF0);
        statusIcon = Icons.info_outline_rounded;
        statusLabel = 'Chưa bắt đầu';
        break;
    }

    final lastCheckInText = lastCheckIn != null
        ? dateFormat.format(lastCheckIn!)
        : 'Chưa có dữ liệu';

    final nextDueText = config?.nextCheckInDueAt != null
        ? dateFormat.format(config!.nextCheckInDueAt!)
        : (lastCheckIn != null
              ? dateFormat.format(lastCheckIn!.add(const Duration(hours: 24)))
              : 'Chưa có lịch');

    final remainingText =
        config?.getRemainingFormatted() ??
        (lastCheckIn != null ? 'Khoảng 24 giờ' : 'Bấm xác nhận để bắt đầu');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hàng tiêu đề trạng thái
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: badgeBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: badgeBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  remainingText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFEEF2F5)),
          const SizedBox(height: 14),

          // Hai cột: Gần nhất & Hạn tiếp theo
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LẦN XÁC NHẬN GẦN NHẤT',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF6B8793),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      lastCheckInText,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF082F49),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: const Color(0xFFEEF2F5),
                margin: const EdgeInsets.symmetric(horizontal: 10),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HẠN XÁC NHẬN TIẾP THEO',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF6B8793),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      nextDueText,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: status == CheckInStatus.overdue
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF082F49),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
