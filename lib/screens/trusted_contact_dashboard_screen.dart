import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';

import '../services/trusted_contact_dashboard_service.dart';

class TrustedContactDashboardScreen extends StatefulWidget {
  const TrustedContactDashboardScreen({super.key});

  @override
  State<TrustedContactDashboardScreen> createState() =>
      _TrustedContactDashboardScreenState();
}

class _TrustedContactDashboardScreenState
    extends State<TrustedContactDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  List<TrustedPerson> _people = [];
  List<Map<String, dynamic>> _invitations = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (Firebase.apps.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = 'Firebase chưa được khởi tạo.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final people = await TrustedContactDashboardService.instance.getPeople();
      final invitations =
          await TrustedContactDashboardService.instance.getInvitations();
      if (!mounted) return;
      setState(() {
        _people = people;
        _invitations = invitations;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F8),
      appBar: AppBar(
        title: const Text('Người tôi theo dõi'),
        backgroundColor: const Color(0xFF082F49),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: const Color(0xFF078D83),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          const Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: Colors.redAccent,
          ),
          const SizedBox(height: 12),
          const Text('Không thể tải dashboard', textAlign: TextAlign.center),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ],
      );
    }
    if (_people.isEmpty && _invitations.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          Icon(Icons.diversity_1_rounded, size: 56, color: Color(0xFF078D83)),
          SizedBox(height: 16),
          Text(
            'Chưa có người được theo dõi',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Email đăng nhập phải được một người khác thêm, xác minh và chấp thuận làm người liên hệ khẩn cấp.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: (_invitations.isEmpty ? 0 : 1) + _people.length,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (_invitations.isNotEmpty && index == 0) {
          return _invitationCard();
        }
        final personIndex = index - (_invitations.isEmpty ? 0 : 1);
        return _personCard(_people[personIndex]);
      },
    );
  }

  Widget _invitationCard() {
    final pending = _invitations.where((item) =>
        item['consentStatus'] != 'accepted').toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    final invitation = pending.first;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lời mời người liên hệ',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('${invitation['ownerName']} đã thêm email của bạn để nhận cảnh báo khẩn cấp.'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _sendVerification,
                  child: const Text('Gửi xác minh Gmail'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => _acceptInvitation(invitation),
                  child: const Text('Đồng ý'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _sendVerification() async {
    try {
      await TrustedContactDashboardService.instance.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã gửi email xác minh Firebase Auth.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _acceptInvitation(Map<String, dynamic> invitation) async {
    try {
      await TrustedContactDashboardService.instance.acceptInvitation(
        invitation['ownerUid'].toString(),
        invitation['contactId'].toString(),
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xác nhận làm người liên hệ khẩn cấp.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Widget _personCard(TrustedPerson person) {
    final status = _statusData(person.status);
    final dateFormat = DateFormat('HH:mm dd/MM/yyyy');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: status.color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: status.color.withValues(alpha: 0.12),
                foregroundColor: status.color,
                child: Icon(status.icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.ownerName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF082F49),
                      ),
                    ),
                    Text(
                      person.relationship,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(
                    color: status.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _detailRow(
            Icons.check_circle_outline_rounded,
            'Check-in cuối',
            person.lastCheckInAt == null
                ? 'Chưa có dữ liệu'
                : dateFormat.format(person.lastCheckInAt!),
          ),
          const SizedBox(height: 8),
          _detailRow(
            Icons.schedule_rounded,
            'Hạn tiếp theo',
            person.nextCheckInDueAt == null
                ? 'Chưa có lịch'
                : dateFormat.format(person.nextCheckInDueAt!),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF52717D)),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(color: Color(0xFF52717D))),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  _StatusData _statusData(String status) {
    switch (status) {
      case 'overdue':
        return const _StatusData(
          'Quá hạn',
          Color(0xFFC62828),
          Icons.priority_high_rounded,
        );
      case 'paused':
        return const _StatusData(
          'Tạm dừng',
          Color(0xFF6B8793),
          Icons.pause_circle_outline_rounded,
        );
      default:
        return const _StatusData(
          'An toàn',
          Color(0xFF078D83),
          Icons.shield_rounded,
        );
    }
  }
}

class _StatusData {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusData(this.label, this.color, this.icon);
}
