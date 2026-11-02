import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/emergency_contact.dart';
import '../services/emergency_contact_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _contactService = EmergencyContactService.instance;
  List<EmergencyContact> _contacts = [];
  bool _isLoading = true;
  String? _errorMessage;
  final Map<String, bool> _sendingVerification = {};

  static const List<String> _relationshipOptions = [
    'Bố / Mẹ',
    'Vợ / Chồng',
    'Con cái',
    'Anh / Chị / Em',
    'Bạn bè thân thiết',
    'Đồng nghiệp',
    'Khác',
  ];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await _contactService.getContacts();
      if (mounted) {
        setState(() {
          _contacts = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Không thể tải danh bạ: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showContactDialog({EmergencyContact? contactToEdit}) async {
    final isEditing = contactToEdit != null;
    final nameController = TextEditingController(
      text: contactToEdit?.name ?? '',
    );
    final emailController = TextEditingController(
      text: contactToEdit?.email ?? '',
    );
    final phoneController = TextEditingController(
      text: contactToEdit?.phoneNumber ?? '',
    );
    String selectedRelationship = contactToEdit?.relationship ?? 'Bố / Mẹ';

    if (!_relationshipOptions.contains(selectedRelationship)) {
      selectedRelationship = 'Khác';
    }

    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD8E2E6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isEditing
                            ? 'Chỉnh sửa liên hệ khẩn cấp'
                            : 'Thêm người liên hệ khẩn cấp',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF082F49),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Người này sẽ nhận được thông báo khi bạn quá hạn an toàn.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF6B8793),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Họ tên
                      TextFormField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Họ và tên *',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        validator: EmergencyContact.validateName,
                      ),
                      const SizedBox(height: 14),

                      // Email
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Địa chỉ Email *',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        validator: EmergencyContact.validateEmail,
                      ),
                      const SizedBox(height: 14),

                      // Số điện thoại (tùy chọn)
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Số điện thoại (Không bắt buộc)',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        validator: EmergencyContact.validatePhone,
                      ),
                      const SizedBox(height: 14),

                      // Mối quan hệ
                      DropdownButtonFormField<String>(
                        initialValue: selectedRelationship,
                        decoration: InputDecoration(
                          labelText: 'Mối quan hệ *',
                          prefixIcon: const Icon(Icons.people_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        items: _relationshipOptions
                            .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => selectedRelationship = val);
                          }
                        },
                      ),
                      const SizedBox(height: 24),

                      // Nút hành động
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Hủy'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF078D83),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () async {
                                if (formKey.currentState?.validate() != true) {
                                  return;
                                }

                                Navigator.pop(ctx);
                                final messenger = ScaffoldMessenger.of(context);

                                try {
                                  if (isEditing) {
                                    final updated = contactToEdit.copyWith(
                                      name: nameController.text.trim(),
                                      email: emailController.text
                                          .trim()
                                          .toLowerCase(),
                                      phoneNumber:
                                          phoneController.text.trim().isEmpty
                                          ? null
                                          : phoneController.text.trim(),
                                      relationship: selectedRelationship,
                                    );
                                    await _contactService.updateContact(
                                      updated,
                                    );
                                    if (mounted) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Đã cập nhật thông tin người liên hệ!',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          backgroundColor: Color(0xFF078D83),
                                        ),
                                      );
                                    }
                                  } else {
                                    await _contactService.addContact(
                                      name: nameController.text.trim(),
                                      email: emailController.text
                                          .trim()
                                          .toLowerCase(),
                                      phoneNumber:
                                          phoneController.text.trim().isEmpty
                                          ? null
                                          : phoneController.text.trim(),
                                      relationship: selectedRelationship,
                                    );
                                    if (mounted) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Đã thêm người liên hệ khẩn cấp mới!',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          backgroundColor: Color(0xFF078D83),
                                        ),
                                      );
                                    }
                                  }
                                  await _loadContacts();
                                } catch (e) {
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Lỗi: $e'),
                                        behavior: SnackBarBehavior.floating,
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Text(
                                isEditing ? 'Cập nhật' : 'Thêm liên hệ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleDelete(EmergencyContact contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xóa liên hệ khẩn cấp?'),
        content: Text(
          'Bạn có chắc chắn muốn xóa "${contact.name}" khỏi danh bạ khẩn cấp? Người này sẽ không nhận được cảnh báo an toàn từ bạn nữa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _contactService.deleteContact(contact.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã xóa "${contact.name}" khỏi danh bạ.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        await _loadContacts();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi khi xóa: $e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleToggleActive(EmergencyContact contact) async {
    try {
      final updated = await _contactService.toggleContactActive(contact);
      if (mounted) {
        setState(() {
          final idx = _contacts.indexWhere((c) => c.id == contact.id);
          if (idx != -1) _contacts[idx] = updated;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              updated.isActive
                  ? 'Đã bật nhận cảnh báo cho ${contact.name}'
                  : 'Đã tạm ngưng nhận cảnh báo cho ${contact.name}',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF078D83),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _handleSendVerification(EmergencyContact contact) async {
    setState(() {
      _sendingVerification[contact.id] = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    final result = await _contactService.requestContactVerification(contact.id);

    if (mounted) {
      setState(() {
        _sendingVerification[contact.id] = false;
      });

      if (!result.success) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        _showVerificationSuccessDialog(contact, result);
        _loadContacts();
      }
    }
  }

  void _showVerificationSuccessDialog(
    EmergencyContact contact,
    VerificationResult result,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.mark_email_read_rounded, color: Color(0xFF078D83)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mã xác minh an toàn',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Đã tạo mã xác minh và ghi nhận token hash an toàn cho "${contact.name}".',
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: result.isDryRun
                      ? const Color(0xFFFFFBEB)
                      : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: result.isDryRun
                        ? const Color(0xFFFDE68A)
                        : const Color(0xFFA7F3D0),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      result.isDryRun
                          ? Icons.science_outlined
                          : Icons.mark_email_read_outlined,
                      size: 18,
                      color: result.isDryRun
                          ? const Color(0xFFD97706)
                          : const Color(0xFF078D83),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: result.isDryRun
                              ? const Color(0xFF92400E)
                              : const Color(0xFF065F46),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (result.verificationUrl != null) ...[
                const SizedBox(height: 14),
                const Text(
                  'Liên kết xác minh (Web Portal):',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF082F49),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: SelectableText(
                    result.verificationUrl!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (result.verificationUrl != null)
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Sao chép link'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: result.verificationUrl!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Đã sao chép liên kết xác minh vào bộ nhớ tạm!',
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Color(0xFF078D83),
                  ),
                );
              },
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF082F49),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryTeal = Color(0xFF078D83);
    const deepOcean = Color(0xFF082F49);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F8),
      appBar: AppBar(
        title: const Text(
          'Danh bạ khẩn cấp',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: deepOcean,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadContacts,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'Thêm người thân',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: () => _showContactDialog(),
      ),
      body: _buildBody(primaryTeal, deepOcean),
    );
  }

  Widget _buildBody(Color primaryTeal, Color deepOcean) {
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
                onPressed: _loadContacts,
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

    if (_contacts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadContacts,
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
                  Icons.people_outline_rounded,
                  size: 50,
                  color: Color(0xFF078D83),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Chưa có liên hệ khẩn cấp nào',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF082F49),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Hãy thêm ít nhất một người thân hoặc bạn bè tin cậy. '
              'Họ sẽ nhận được cảnh báo tự động kèm thông tin an toàn khi bạn quá hạn điểm danh.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6B8793),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryTeal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => _showContactDialog(),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text(
                  'Thêm liên hệ đầu tiên',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadContacts,
      color: primaryTeal,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        itemCount: _contacts.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildHeaderNotice(primaryTeal, deepOcean);
          }
          final contact = _contacts[index - 1];
          return _buildContactCard(contact, primaryTeal, deepOcean);
        },
      ),
    );
  }

  Widget _buildHeaderNotice(Color primaryTeal, Color deepOcean) {
    final activeCount = _contacts.where((c) => c.isActive).length;

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
                'DANH BẠ TIN CẬY',
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
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$activeCount / ${_contacts.length} Đang kích hoạt',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF34D399),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Khi bạn quá hạn xác nhận an toàn và hết thời gian gia hạn, hệ thống sẽ gửi thông báo khẩn cấp đến các người thân được kích hoạt dưới đây.',
            style: TextStyle(
              color: Color(0xFFD2EAE9),
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(
    EmergencyContact contact,
    Color primaryTeal,
    Color deepOcean,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: contact.isActive
              ? const Color(0xFFE2EBF0)
              : const Color(0xFFECEFF1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hàng 1: Avatar, Tên, Switch Active
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: contact.isActive
                      ? primaryTeal.withValues(alpha: 0.12)
                      : const Color(0xFFECEFF1),
                  child: Text(
                    contact.name.isNotEmpty
                        ? contact.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: contact.isActive
                          ? primaryTeal
                          : const Color(0xFF90A4AE),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              contact.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: contact.isActive
                                    ? deepOcean
                                    : const Color(0xFF90A4AE),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0F7F2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              contact.relationship,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF078D83),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        contact.email,
                        style: TextStyle(
                          fontSize: 13,
                          color: contact.isActive
                              ? const Color(0xFF52717D)
                              : const Color(0xFFB0BEC5),
                        ),
                      ),
                      if (contact.phoneNumber != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          contact.phoneNumber!,
                          style: TextStyle(
                            fontSize: 12,
                            color: contact.isActive
                                ? const Color(0xFF6B8793)
                                : const Color(0xFFCFD8DC),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(
                  value: contact.isActive,
                  activeThumbColor: primaryTeal,
                  onChanged: (val) => _handleToggleActive(contact),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF0F4F7)),
            const SizedBox(height: 10),

            // Hàng 2: Badges trạng thái xác minh & Sự đồng ý
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildStatusChip(
                  label: contact.emailVerified
                      ? 'Email đã xác minh'
                      : 'Email chưa xác minh',
                  icon: contact.emailVerified
                      ? Icons.verified_rounded
                      : Icons.pending_outlined,
                  isPositive: contact.emailVerified,
                ),
                _buildConsentChip(contact.consentStatus),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Chỉnh sửa',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: const Color(0xFF078D83),
                  onPressed: () => _showContactDialog(contactToEdit: contact),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Xóa',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: const Color(0xFFE53935),
                  onPressed: () => _handleDelete(contact),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                ),
              ],
            ),

            // Hàng 3: Nút gửi link xác minh & Opt-In (chỉ hiển thị khi chưa xác minh hoặc chờ/thu hồi đồng ý)
            if (!contact.emailVerified ||
                contact.consentStatus == ConsentStatus.pending ||
                contact.consentStatus == ConsentStatus.revoked) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF078D83),
                    side: const BorderSide(color: Color(0xFF078D83), width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 10,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: _sendingVerification[contact.id] == true
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF078D83),
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 14),
                  label: Text(
                    contact.emailVerified
                        ? (contact.consentStatus == ConsentStatus.revoked
                              ? 'Gửi lại link đề nghị kết nối lại'
                              : 'Gửi lại link xác nhận đồng ý')
                        : 'Gửi link xác minh & đồng ý',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: _sendingVerification[contact.id] == true
                      ? null
                      : () => _handleSendVerification(contact),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required IconData icon,
    required bool isPositive,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isPositive ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPositive ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isPositive
                ? const Color(0xFF059669)
                : const Color(0xFFD97706),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isPositive
                  ? const Color(0xFF059669)
                  : const Color(0xFFD97706),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsentChip(String consentStatus) {
    final String label;
    final Color bgColor;
    final Color textColor;
    final Color borderColor;

    switch (consentStatus) {
      case ConsentStatus.accepted:
        label = 'Đã đồng ý nhận tin';
        bgColor = const Color(0xFFECFDF5);
        textColor = const Color(0xFF059669);
        borderColor = const Color(0xFFA7F3D0);
        break;
      case ConsentStatus.declined:
        label = 'Đã từ chối';
        bgColor = const Color(0xFFFEF2F2);
        textColor = const Color(0xFFDC2626);
        borderColor = const Color(0xFFFECACA);
        break;
      case ConsentStatus.revoked:
        label = 'Đã thu hồi đồng ý';
        bgColor = const Color(0xFFF8FAFC);
        textColor = const Color(0xFF64748B);
        borderColor = const Color(0xFFCBD5E1);
        break;
      case ConsentStatus.pending:
      default:
        label = 'Chờ người nhận đồng ý';
        bgColor = const Color(0xFFF0F9FF);
        textColor = const Color(0xFF0284C7);
        borderColor = const Color(0xFFBAE6FD);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
