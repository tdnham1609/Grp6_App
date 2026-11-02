import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { AlertEvent, AlertLocationData, AlertRecipientRecord, CheckInSettings, EmergencyContactDoc } from './types';
import { EmailService } from './emailService';
import { reverseGeocodeAddress } from './reverseGeocoding';

const DEMO_ALERT_COOLDOWN_MS = 60 * 1000;

/** Send a clearly labeled real email to contacts who verified and accepted alerts. */
export const sendDemoAlert = onCall(
  {
    secrets: ['SEND_DEMO_ALERTS', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM'],
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Vui lòng đăng nhập để gửi email demo.');
    }

    const emailService = new EmailService();
    if (!emailService.hasValidConfiguration(true)) {
      throw new HttpsError(
        'failed-precondition',
        'Email demo chưa được cấu hình. Hãy thiết lập SMTP và bật SEND_DEMO_ALERTS trên Firebase.',
      );
    }

    const db = getFirestore();
    const userRef = db.collection('users').doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new HttpsError('failed-precondition', 'Không tìm thấy hồ sơ người dùng.');
    }

    const contactsSnap = await userRef
      .collection('emergency_contacts')
      .where('isActive', '==', true)
      .get();
    const eligibleContacts = contactsSnap.docs
      .map((doc) => doc.data() as EmergencyContactDoc)
      .filter((contact) => contact.emailVerified === true && contact.consentStatus === 'accepted');

    if (eligibleContacts.length === 0) {
      throw new HttpsError(
        'failed-precondition',
        'Chưa có liên hệ đang hoạt động đã xác minh email và đồng ý nhận cảnh báo.',
      );
    }

    const now = Timestamp.now();
    const cooldownRef = db.collection('demo_alert_rate_limits').doc(uid);
    await db.runTransaction(async (transaction) => {
      const cooldownSnap = await transaction.get(cooldownRef);
      const lastSentAt = cooldownSnap.get('lastSentAt') as Timestamp | undefined;
      if (lastSentAt && now.toMillis() - lastSentAt.toMillis() < DEMO_ALERT_COOLDOWN_MS) {
        throw new HttpsError(
          'resource-exhausted',
          'Vui lòng chờ một phút trước khi gửi email demo tiếp theo.',
        );
      }
      transaction.set(cooldownRef, { lastSentAt: now });
    });

    const eventId = `demo_${now.toMillis()}`;
    const eventRef = userRef.collection('alert_events').doc(eventId);
    const pendingRecipients: AlertRecipientRecord[] = eligibleContacts.map((contact) => ({
      contactId: contact.id,
      email: contact.email,
      name: contact.name,
      status: 'pending',
      sentAt: null,
      error: null,
      attempts: 0,
    }));

    const event: AlertEvent = {
      id: eventId,
      uid,
      isDemo: true,
      checkInDueAt: now,
      gracePeriodEndsAt: now,
      status: 'pending_alert',
      detectedAt: now,
      resolvedAt: null,
      cancellationReason: null,
      recipients: pendingRecipients,
    };
    await eventRef.set(event);

    const userName = userSnap.data()?.displayName || 'Người dùng Sinh Tử';
    const settingsSnap = await userRef.collection('settings').doc('checkin').get();
    const settings = settingsSnap.data() as CheckInSettings | undefined;
    const savedLocation = settings?.lastKnownLocation;
    let location: AlertLocationData | null = null;
    if (
      settings?.isLocationSharingEnabled === true &&
      savedLocation &&
      Number.isFinite(savedLocation.latitude) &&
      Number.isFinite(savedLocation.longitude)
    ) {
      location = {
        latitude: savedLocation.latitude,
        longitude: savedLocation.longitude,
        accuracy: savedLocation.accuracy,
        timestamp: savedLocation.timestamp,
        isSharingEnabled: true,
        address: await reverseGeocodeAddress(savedLocation.latitude, savedLocation.longitude),
      };
    }

    const recipientResults: AlertRecipientRecord[] = [];
    for (const contact of eligibleContacts) {
      const result = await emailService.sendAlertEmail({
        recipient: {
          contactId: contact.id,
          email: contact.email,
          name: contact.name,
        },
        userName,
        dueDate: now.toDate(),
        gracePeriodEndsAt: now.toDate(),
        location,
        isDemo: true,
      });
      if (result.status === 'sent') result.sentAt = Timestamp.now();
      recipientResults.push(result);

      await eventRef.set({ recipients: recipientResults }, { merge: true });
    }

    const sentCount = recipientResults.filter((recipient) => recipient.status === 'sent').length;
    const failedCount = recipientResults.length - sentCount;
    const status = sentCount === recipientResults.length
      ? 'alert_sent'
      : sentCount > 0
        ? 'partially_sent'
        : 'alert_failed';

    await eventRef.set(
      { status, resolvedAt: Timestamp.now(), recipients: recipientResults },
      { merge: true },
    );

    logger.info(`[DemoAlert] Demo event ${eventId} completed for ${uid}: ${sentCount}/${recipientResults.length} sent.`);
    return {
      eventId,
      sentCount,
      failedCount,
      totalCount: recipientResults.length,
      recipients: recipientResults.map(({ name, email, status: recipientStatus }) => ({
        name,
        email,
        status: recipientStatus,
      })),
    };
  },
);
