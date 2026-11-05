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

  Future<void> sendEmailVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Bạn cần đăng nhập trước.');
    if (user.emailVerified) return;
    await user.sendEmailVerification();
  }

  Future<List<Map<String, dynamic>>> getInvitations() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim().toLowerCase();
    if (user == null || email == null || email.isEmpty) return [];

    final snapshot = await FirebaseFirestore.instance
        .collection('contactInvitations')
        .where('recipientEmail', isEqualTo: email)
        .get();

    return snapshot.docs.map((document) {
      final data = document.data();
      data['id'] = document.id;
      return data;
    }).toList();
  }

  Future<List<TrustedPerson>> getPeople() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim().toLowerCase();
    if (user == null || email == null || email.isEmpty) return [];

    final firestore = FirebaseFirestore.instance;
    final invitationSnapshot = await firestore
        .collection('contactInvitations')
        .where('recipientEmail', isEqualTo: email)
        .get();

    final invited = <TrustedPerson>{};
    for (final document in invitationSnapshot.docs) {
      final data = document.data();
      if (data['consentStatus'] == 'accepted' &&
          data['emailVerified'] == true) {
        invited.add(TrustedPerson(
          ownerUid: data['ownerUid']?.toString() ?? '',
          ownerName: data['ownerName']?.toString() ?? 'Người cần theo dõi',
          relationship: data['relationship']?.toString() ?? 'Người thân',
          lastCheckInAt: (data['lastCheckInAt'] as Timestamp?)?.toDate().toLocal(),
          nextCheckInDueAt: (data['nextCheckInDueAt'] as Timestamp?)?.toDate().toLocal(),
          isDeadManSwitchActive: data['isDeadManSwitchActive'] != false,
          status: data['isDeadManSwitchActive'] == false
              ? 'paused'
              : (data['nextCheckInDueAt'] as Timestamp?)?.toDate().isBefore(DateTime.now()) == true
                  ? 'overdue'
                  : 'safe',
          latestAlertStatus: data['latestAlertStatus']?.toString(),
        ));
      }
    }

    final snapshot = await firestore
        .collection('trustedStatuses')
        .where('trustedEmails', arrayContains: email)
        .get();

    for (final document in snapshot.docs) {
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

      invited.add(TrustedPerson(
        ownerUid: document.id,
        ownerName: data['ownerName']?.toString() ?? 'Người cần theo dõi',
        relationship: data['relationship']?.toString() ?? 'Người thân',
        lastCheckInAt: lastCheckIn?.toDate().toLocal(),
        nextCheckInDueAt: nextDue?.toDate().toLocal(),
        isDeadManSwitchActive: active,
        status: status,
        latestAlertStatus: data['latestAlertStatus']?.toString(),
      ));
    }

    return invited.toList();
  }

  Future<void> acceptInvitation(String ownerUid, String contactId) async {
    final user = FirebaseAuth.instance.currentUser;
    await user?.reload();
    final currentUser = FirebaseAuth.instance.currentUser;
    final email = currentUser?.email?.trim().toLowerCase();

    if (currentUser == null || email == null || email.isEmpty) {
      throw StateError('Bạn cần đăng nhập bằng tài khoản Gmail.');
    }
    if (currentUser.emailVerified != true) {
      throw StateError('Vui lòng xác minh email trong Firebase Auth trước.');
    }

    final firestore = FirebaseFirestore.instance;
    final invitationRef = firestore
        .collection('contactInvitations')
        .doc('${ownerUid}_$contactId');
    final invitation = await invitationRef.get();
    if (!invitation.exists || invitation.data()?['recipientEmail'] != email) {
      throw StateError('Lời mời không thuộc tài khoản Gmail này.');
    }

    final contactRef = firestore
        .collection('users')
        .doc(ownerUid)
        .collection('emergency_contacts')
        .doc(contactId);
    final batch = firestore.batch();
    batch.update(contactRef, {
      'emailVerified': true,
      'consentStatus': 'accepted',
      'consentUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(invitationRef, {
      'emailVerified': true,
      'consentStatus': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
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

    for (final contact in contacts.docs) {
      final data = contact.data();
      final email = data['email']?.toString().trim().toLowerCase() ?? '';
      if (email.isEmpty) continue;

      await firestore
          .collection('contactInvitations')
          .doc('${user.uid}_${contact.id}')
          .set({
        'ownerUid': user.uid,
        'contactId': contact.id,
        'ownerName': user.displayName ?? 'Người cần theo dõi',
        'recipientName': data['name']?.toString() ?? '',
        'recipientEmail': email,
        'relationship': data['relationship']?.toString() ?? 'Người thân',
        'isActive': data['isActive'] != false,
        'emailVerified': data['emailVerified'] == true,
        'consentStatus': data['consentStatus']?.toString() ?? 'pending',
        'lastCheckInAt': config.lastCheckInAt == null
            ? null
            : Timestamp.fromDate(config.lastCheckInAt!),
        'nextCheckInDueAt': config.nextCheckInDueAt == null
            ? null
            : Timestamp.fromDate(config.nextCheckInDueAt!),
        'isDeadManSwitchActive': config.isDeadManSwitchActive,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}
