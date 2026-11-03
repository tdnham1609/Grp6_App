import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/check_in_config.dart';

class TrustedPerson {
  final String ownerUid;
  final String ownerName;
  final String relationship;
  final DateTime? lastCheckInAt;
  final DateTime? nextCheckInDueAt;
  final bool isDeadManSwitchActive;
  final String status;
  final String? latestAlertStatus;

  const TrustedPerson({
    required this.ownerUid,
    required this.ownerName,
    required this.relationship,
    required this.lastCheckInAt,
    required this.nextCheckInDueAt,
    required this.isDeadManSwitchActive,
    required this.status,
    required this.latestAlertStatus,
  });

  factory TrustedPerson.fromMap(Map<Object?, Object?> raw) {
    DateTime? parseDate(Object? value) {
      if (value is! String || value.isEmpty) return null;
      return DateTime.tryParse(value)?.toLocal();
    }

    return TrustedPerson(
      ownerUid: raw['ownerUid']?.toString() ?? '',
      ownerName: raw['ownerName']?.toString() ?? 'Người cần theo dõi',
      relationship: raw['relationship']?.toString() ?? 'Người thân',
      lastCheckInAt: parseDate(raw['lastCheckInAt']),
      nextCheckInDueAt: parseDate(raw['nextCheckInDueAt']),
      isDeadManSwitchActive: raw['isDeadManSwitchActive'] == true,
      status: raw['status']?.toString() ?? 'safe',
      latestAlertStatus: raw['latestAlertStatus']?.toString(),
    );
  }
}

class TrustedContactDashboardService {
  TrustedContactDashboardService._();

  static final TrustedContactDashboardService instance =
      TrustedContactDashboardService._();

  Future<List<TrustedPerson>> getPeople() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim().toLowerCase();
    if (user == null || email == null || email.isEmpty) return [];

    final snapshot = await FirebaseFirestore.instance
        .collection('trustedStatuses')
        .where('trustedEmails', arrayContains: email)
        .get();

    return snapshot.docs.map((document) {
      final data = document.data();
      final nextDue = data['nextCheckInDueAt'] as Timestamp?;
      final lastCheckIn = data['lastCheckInAt'] as Timestamp?;
      final overdue =
          nextDue != null && nextDue.toDate().isBefore(DateTime.now());
      final active = data['isDeadManSwitchActive'] != false;
      final status = !active
          ? 'paused'
          : overdue
          ? 'overdue'
          : 'safe';

      return TrustedPerson(
        ownerUid: document.id,
        ownerName: data['ownerName']?.toString() ?? 'Người cần theo dõi',
        relationship: data['relationship']?.toString() ?? 'Người thân',
        lastCheckInAt: lastCheckIn?.toDate().toLocal(),
        nextCheckInDueAt: nextDue?.toDate().toLocal(),
        isDeadManSwitchActive: active,
        status: status,
        latestAlertStatus: data['latestAlertStatus']?.toString(),
      );
    }).toList();
  }

  Future<void> syncMyStatus([CheckInConfig? providedConfig]) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firestore = FirebaseFirestore.instance;
    final contacts = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('emergency_contacts')
        .where('isActive', isEqualTo: true)
        .get();

    final trustedEmails = <String>{};
    for (final contact in contacts.docs) {
      final data = contact.data();
      if (data['emailVerified'] == true &&
          data['consentStatus'] == 'accepted') {
        final email = data['email']?.toString().trim().toLowerCase();
        if (email != null && email.isNotEmpty) trustedEmails.add(email);
      }
    }

    CheckInConfig? config = providedConfig;
    if (config == null) {
      final settingsSnapshot = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('checkin')
          .get();
      final settings = settingsSnapshot.data();
      if (settings != null) config = CheckInConfig.fromMap(settings);
    }
    config ??= CheckInConfig.defaultConfig();

    await firestore.collection('trustedStatuses').doc(user.uid).set({
      'ownerUid': user.uid,
      'ownerName': user.displayName ?? 'Người cần theo dõi',
      'relationship': 'Người thân khẩn cấp',
      'trustedEmails': trustedEmails.toList(),
      'relationshipsUpdatedAt': FieldValue.serverTimestamp(),
      'isDeadManSwitchActive': config.isDeadManSwitchActive,
      'lastCheckInAt': config.lastCheckInAt == null
          ? null
          : Timestamp.fromDate(config.lastCheckInAt!),
      'nextCheckInDueAt': config.nextCheckInDueAt == null
          ? null
          : Timestamp.fromDate(config.nextCheckInDueAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
