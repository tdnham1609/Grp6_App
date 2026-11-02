import 'package:flutter/material.dart';

import '../models/check_in_config.dart';
import '../widgets/check_in_button.dart';
import '../widgets/status_card.dart';
import '../widgets/feature_card.dart';

class HomeScreen extends StatelessWidget {
  final DateTime? lastCheckIn;
  final CheckInConfig? config;
  final VoidCallback onCheckIn;
  final VoidCallback onOpenContacts;

  const HomeScreen({
    super.key,
    required this.lastCheckIn,
    this.config,
    required this.onCheckIn,
    required this.onOpenContacts,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF062C43),
                  Color(0xFF075B65),
                  Color(0xFF078D83),
                ],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.shield_moon_rounded,
                          color: Color(0xFF50E3C2),
                          size: 38,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SINH TỬ',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                              Text(
                                'Kết nối sự sống',
                                style: TextStyle(
                                  color: Color(0xFFC7EAE7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Chưa có thông báo mới.'),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.notifications_none_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Container(
                      width: 132,
                      height: 132,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF50E3C2),
                          width: 2,
                        ),
                        color: Colors.white.withValues(alpha: 0.1),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF50E3C2)
                                .withValues(alpha: 0.15),
                            blurRadius: 25,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        size: 76,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Bạn vẫn an toàn chứ?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Một lần xác nhận nhỏ, thêm sự yên tâm '
                      'cho những người thân yêu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFD2EAE9),
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 25),
                    StatusCard(lastCheckIn: lastCheckIn, config: config),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              CheckInButton(onPressed: onCheckIn),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F7F2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFC4EDE5)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notifications_active_rounded,
                      color: Color(0xFF078D83),
                      size: 27,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nhắc nhở an toàn',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF082F49),
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Theo dõi thời gian xác nhận và '
                            'nhắc bạn kiểm tra trạng thái định kỳ.',
                            style: TextStyle(
                              color: Color(0xFF52717D),
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'KẾT NỐI AN TOÀN',
                style: TextStyle(
                  color: Color(0xFF45616D),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  Expanded(
                    child: FeatureCard(
                      icon: Icons.people_alt_rounded,
                      title: 'Danh bạ',
                      subtitle: 'Liên hệ khẩn cấp',
                      backgroundColor: const Color(0xFFFFE9E5),
                      iconColor: const Color(0xFFE36F61),
                      onTap: onOpenContacts,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FeatureCard(
                      icon: Icons.location_on_rounded,
                      title: 'Vị trí',
                      subtitle: 'GPS thiết bị',
                      backgroundColor: const Color(0xFFE0F1FF),
                      iconColor: const Color(0xFF2588C7),
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Vị trí của bạn'),
                            content: const Text(
                              'Chức năng GPS sẽ được bổ sung ở bước tiếp theo.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Đóng'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'Sống an toàn, kết nối yêu thương.',
                  style: TextStyle(
                    color: Color(0xFF078D83),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
