import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { CheckInSettings, AlertEvent, AlertRecipientRecord, EmergencyContactDoc, AlertStatus } from './types';
import { evaluateDeadManSwitch, DEFAULT_GRACE_PERIOD_MINUTES } from './safetyEngine';
import { EmailService } from './emailService';
import { reverseGeocodeAddress } from './reverseGeocoding';

/**
 * Xử lý kiểm tra và gửi cảnh báo quá hạn cho một người dùng cụ thể
 * Tách biệt để hỗ trợ kiểm thử đơn vị và tích hợp độc lập
 */
export async function processSingleUserCheckIn(params: {
  db: FirebaseFirestore.Firestore;
  userRef: FirebaseFirestore.DocumentReference;
  settingsDoc: FirebaseFirestore.DocumentSnapshot;
  now: Date;
  emailService?: EmailService;
  ignorePreviousAlerts?: boolean;
}): Promise<{
  action: string;
  status?: AlertStatus;
  eventId?: string;
  recipientsCount?: number;
}> {
  const { db, userRef, settingsDoc, now, ignorePreviousAlerts = false } = params;
  const emailService = params.emailService || new EmailService();
  const nowTimestamp = Timestamp.fromDate(now);
  const uid = userRef.id;

  const settings = settingsDoc.data() as CheckInSettings;
  if (settings.isDeadManSwitchActive === false || !settings.nextCheckInDueAt) {
    return { action: 'NO_ACTION' };
  }

  const alertEventsRef = userRef.collection('alert_events');

  // Tìm sự kiện cảnh báo gần nhất
  const recentAlertsSnapshot = await alertEventsRef
    .orderBy('detectedAt', 'desc')
    .limit(1)
    .get();

  const existingAlertDoc = recentAlertsSnapshot.docs[0];
  const existingAlert = existingAlertDoc
    ? (existingAlertDoc.data() as AlertEvent)
    : null;

  const dueDate = settings.nextCheckInDueAt.toDate();
  const eventId = `event_${dueDate.getTime()}`;
  const targetEventRef = alertEventsRef.doc(eventId);

  // 1. Đọc và lọc danh bạ khẩn cấp trước khi vào transaction
  // Ràng buộc bảo mật: Chỉ liên hệ Active + Email Verified + Consent Accepted
  let eligibleContacts: EmergencyContactDoc[] = [];
  try {
    const contactsSnap = await userRef
      .collection('emergency_contacts')
      .where('isActive', '==', true)
      .get();

    eligibleContacts = contactsSnap.docs
      .map((d) => d.data() as EmergencyContactDoc)
      .filter((c) => c.emailVerified === true && c.consentStatus === 'accepted');
  } catch (contactErr) {
    logger.warn(`[DeadManSwitch] Lỗi truy vấn danh bạ khẩn cấp cho ${uid}:`, contactErr);
  }

  let claimForSending = false;
  let evaluatedAction = 'NO_ACTION';
  let targetGraceEndsAt: Date = new Date(dueDate.getTime() + DEFAULT_GRACE_PERIOD_MINUTES * 60 * 1000);
  let freshSettingsSnapshot: CheckInSettings = settings;

  // 2. Chạy Firestore Transaction để đọc dữ liệu mới nhất và claim event (Chống Race Condition & Trùng lặp)
  await db.runTransaction(async (transaction) => {
    const freshSettingsSnap = await transaction.get(settingsDoc.ref);
    if (!freshSettingsSnap.exists) {
      evaluatedAction = 'NO_ACTION';
      return;
    }

    const freshSettings = freshSettingsSnap.data() as CheckInSettings;
    freshSettingsSnapshot = freshSettings;
    if (freshSettings.isDeadManSwitchActive === false || !freshSettings.nextCheckInDueAt) {
      evaluatedAction = 'NO_ACTION';
      return;
    }

    const targetEventSnap = await transaction.get(targetEventRef);
    const freshAlert = targetEventSnap.exists
      ? (targetEventSnap.data() as AlertEvent)
      : ignorePreviousAlerts
        ? null
        : existingAlert;

    // Đánh giá an toàn cốt lõi
    const evaluation = evaluateDeadManSwitch({
      now,
      settings: freshSettings,
      existingAlert: freshAlert,
    });

    evaluatedAction = evaluation.action;
    const currentDueDate = freshSettings.nextCheckInDueAt.toDate();
    targetGraceEndsAt =
      evaluation.gracePeriodEndsAt ||
      (freshAlert
        ? freshAlert.gracePeriodEndsAt.toDate()
        : new Date(currentDueDate.getTime() + DEFAULT_GRACE_PERIOD_MINUTES * 60 * 1000));

    switch (evaluation.action) {
      case 'START_GRACE_PERIOD': {
        const newEvent: AlertEvent = {
          id: eventId,
          uid,
          checkInDueAt: freshSettings.nextCheckInDueAt!,
          gracePeriodEndsAt: Timestamp.fromDate(targetGraceEndsAt),
          status: 'overdue',
          detectedAt: nowTimestamp,
          resolvedAt: null,
          cancellationReason: null,
          dryRunDetails: null,
        };

        transaction.set(targetEventRef, newEvent, { merge: true });
        break;
      }

      case 'TRIGGER_DRY_RUN': {
        // Kiểm tra xem backend đã được cấu hình gửi email thật hay đang ở chế độ Dry-Run mặc định
        const isRealEmailConfigured = emailService.hasValidConfiguration();

        if (!isRealEmailConfigured) {
          // CHẾ ĐỘ DRY-RUN MẶC ĐỊNH: Tuyệt đối không gửi email thật
          const skippedRecipients: AlertRecipientRecord[] = eligibleContacts.map((c) => ({
            contactId: c.id,
            email: c.email,
            name: c.name,
            status: 'skipped_dry_run',
            sentAt: null,
            error: null,
            attempts: 0,
          }));

          const dryRunData: AlertEvent = {
            id: eventId,
            uid,
            checkInDueAt: freshSettings.nextCheckInDueAt!,
            gracePeriodEndsAt: Timestamp.fromDate(targetGraceEndsAt),
            status: 'dry_run_dispatched',
            detectedAt: freshAlert ? freshAlert.detectedAt : nowTimestamp,
            resolvedAt: nowTimestamp,
            cancellationReason: null,
            recipients: skippedRecipients,
            dryRunDetails: {
              isDryRun: true,
              simulatedRecipientsCount: eligibleContacts.length,
              simulatedMessage: `[DRY-RUN] CẢNH BÁO SINH TỬ: Quá hạn xác nhận kể từ ${currentDueDate.toISOString()}. Số người nhận mô phỏng: ${eligibleContacts.length}.`,
              evaluatedAt: nowTimestamp,
            },
          };

          transaction.set(targetEventRef, dryRunData, { merge: true });
          claimForSending = false;
        } else {
          // CHẾ ĐỘ GỬI THẬT: Khóa trạng thái pending_alert trong transaction để chống gửi trùng lặp
          const claimEvent: AlertEvent = {
            id: eventId,
            uid,
            checkInDueAt: freshSettings.nextCheckInDueAt!,
            gracePeriodEndsAt: Timestamp.fromDate(targetGraceEndsAt),
            status: 'pending_alert',
            detectedAt: freshAlert ? freshAlert.detectedAt : nowTimestamp,
            resolvedAt: null,
            cancellationReason: null,
          };
          transaction.set(targetEventRef, claimEvent, { merge: true });
          claimForSending = true;
        }
        break;
      }

      case 'CANCEL_ALERT': {
        if (existingAlertDoc) {
          transaction.update(existingAlertDoc.ref, {
            status: 'cancelled',
            resolvedAt: nowTimestamp,
            cancellationReason: evaluation.reason,
          });
        }
        break;
      }

      case 'NO_ACTION':
      default:
        break;
    }
  });

  // 3. Nếu được claim gửi thật -> Thực hiện gửi ngoài Transaction (tránh giữ transaction lock lâu)
  if (claimForSending) {
    const currentDueDate = freshSettingsSnapshot.nextCheckInDueAt!.toDate();

    // Đọc lại recipients MỚI NHẤT từ Firestore để đảm bảo idempotency chính xác
    // (tránh trường hợp Function retry sau crash, dùng cache cũ)
    const freshEventSnap = await targetEventRef.get();
    const persistedRecipients = freshEventSnap.data()?.recipients as AlertRecipientRecord[] | undefined;

    // Lấy tên hiển thị của người dùng
    const userDocSnap = await db.collection('users').doc(uid).get();
    const userDisplayName = userDocSnap.data()?.displayName || 'Người dùng Sinh Tử';

    const recipientResults: AlertRecipientRecord[] = [];
    const sharedLocation =
      freshSettingsSnapshot.isLocationSharingEnabled && freshSettingsSnapshot.lastKnownLocation
        ? freshSettingsSnapshot.lastKnownLocation
        : null;
    const locationPayload = sharedLocation
      ? {
          latitude: sharedLocation.latitude,
          longitude: sharedLocation.longitude,
          accuracy: sharedLocation.accuracy,
          timestamp: sharedLocation.timestamp,
          isSharingEnabled: true,
          address: await reverseGeocodeAddress(sharedLocation.latitude, sharedLocation.longitude),
        }
      : null;

    // Gửi lần lượt cho từng người nhận (cô lập lỗi, gửi lỗi người này không ảnh hưởng người khác)
    for (const contact of eligibleContacts) {
      // Idempotency per recipient: Đọc trạng thái đã persisted để tránh gửi lại sau crash/retry
      const alreadySent = persistedRecipients?.find(
        (r) => r.contactId === contact.id && r.status === 'sent'
      );

      if (alreadySent) {
        logger.info(
          `[DeadManSwitch] Bỏ qua ${contact.email} (contactId: ${contact.id}) — đã gửi thành công trước đó (idempotency).`
        );
        recipientResults.push(alreadySent);
        continue;
      }

      const projectId = process.env.GCLOUD_PROJECT || 'sinhtuapp';
      const revokeConsentUrl = `https://us-central1-${projectId}.cloudfunctions.net/verifyContactPortal`;

      const delivery = await emailService.sendAlertEmail({
        recipient: {
          contactId: contact.id,
          email: contact.email,
          name: contact.name,
        },
        userName: userDisplayName,
        dueDate: currentDueDate,
        gracePeriodEndsAt: targetGraceEndsAt,
        location: locationPayload,
        revokeConsentUrl,
      });

      if (delivery.status === 'sent') {
        delivery.sentAt = nowTimestamp;
      }

      recipientResults.push(delivery);

      // ─── INCREMENTAL FLUSH ───────────────────────────────────────────────────
      // Ghi kết quả từng người ngay sau khi gửi (dù thành công hay thất bại).
      // Đây là cơ chế chống gửi trùng quan trọng nhất:
      // Nếu Function crash sau khi SMTP nhận thư nhưng TRƯỚC khi ghi Firestore cuối cùng,
      // lần retry tiếp theo sẽ đọc được trạng thái 'sent' đã persisted và bỏ qua.
      try {
        await targetEventRef.set(
          { recipients: recipientResults },
          { merge: true }
        );
      } catch (flushErr) {
        logger.warn(
          `[DeadManSwitch] Không thể flush trạng thái sau khi gửi cho ${contact.email}:`,
          flushErr
        );
        // Không throw — tiếp tục gửi cho những người nhận còn lại
      }
    }

    // Đánh giá trạng thái tổng thể dựa trên kết quả từng người nhận
    const sentCount = recipientResults.filter((r) => r.status === 'sent').length;
    const failedCount = recipientResults.filter((r) => r.status === 'failed').length;

    let finalStatus: AlertStatus = 'alert_sent';
    if (eligibleContacts.length === 0) {
      finalStatus = 'alert_sent'; // Không có người nhận hợp lệ
    } else if (sentCount === eligibleContacts.length) {
      finalStatus = 'alert_sent';
    } else if (sentCount > 0 && failedCount > 0) {
      finalStatus = 'partially_sent';
    } else {
      finalStatus = 'alert_failed';
    }

    // Ghi trạng thái cuối cùng (finalStatus + resolvedAt)
    await targetEventRef.set(
      {
        status: finalStatus,
        resolvedAt: nowTimestamp,
        recipients: recipientResults,
      },
      { merge: true }
    );

    return {
      action: 'TRIGGER_REAL_ALERT',
      status: finalStatus,
      eventId,
      recipientsCount: sentCount,
    };
  }

  return {
    action: evaluatedAction,
    eventId,
    recipientsCount: eligibleContacts.length,
  };
}

/**
 * Scheduled Cloud Function chạy định kỳ mỗi 15 phút
 */
export const checkOverdueDeadManSwitch = onSchedule(
  {
    // Production Cloud Scheduler cadence. The local demo invokes this processing
    // logic through runOverdueDemoCheck because the Emulator does not run schedules.
    schedule: 'every 15 minutes',
    timeZone: 'Asia/Ho_Chi_Minh',
    retryCount: 1,
    memory: '256MiB',
    // Khai báo secrets để Firebase Runtime inject vào process.env khi Function chạy.
    // Secrets được lưu mã hoá trong Google Secret Manager — không bao giờ xuất hiện trong logs hoặc mã nguồn.
    secrets: ['SEND_REAL_ALERTS', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM'],
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const emailService = new EmailService();

    logger.info(`[DeadManSwitch] Bắt đầu chu kỳ quét định kỳ lúc: ${now.toISOString()}`);

    try {
      const settingsSnapshot = await db.collectionGroup('settings').get();
      const checkInDocs = settingsSnapshot.docs.filter((doc) => doc.id === 'checkin');

      logger.info(`[DeadManSwitch] Tìm thấy ${checkInDocs.length} tài khoản có cấu hình check-in.`);

      let processedCount = 0;
      let gracePeriodCount = 0;
      let alertTriggeredCount = 0;
      let cancelledCount = 0;

      for (const doc of checkInDocs) {
        const userRef = doc.ref.parent.parent;
        if (!userRef) continue;

        const result = await processSingleUserCheckIn({
          db,
          userRef,
          settingsDoc: doc,
          now,
          emailService,
        });

        if (result.action === 'START_GRACE_PERIOD') gracePeriodCount++;
        if (result.action === 'TRIGGER_DRY_RUN' || result.action === 'TRIGGER_REAL_ALERT') {
          alertTriggeredCount++;
        }
        if (result.action === 'CANCEL_ALERT') cancelledCount++;

        processedCount++;
      }

      logger.info(
        `[DeadManSwitch] Hoàn thành chu kỳ quét: Đã duyệt ${processedCount} tài khoản (Gia hạn: ${gracePeriodCount}, Kích hoạt cảnh báo: ${alertTriggeredCount}, Tự động huỷ: ${cancelledCount}).`
      );
    } catch (err) {
      logger.error('[DeadManSwitch] Lỗi trong quá trình quét định kỳ:', err);
      throw err;
    }
  }
);

/**
 * Local-only trigger for the classroom overdue demo.
 * The Firebase Emulator Suite does not run Cloud Scheduler jobs on a clock,
 * so the app calls this after the demo grace period. It processes only the
 * signed-in user's own check-in settings and is disabled outside the emulator.
 */
export const runOverdueDemoCheck = onCall(
  {
    timeoutSeconds: 30,
    secrets: ['SEND_REAL_ALERTS', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM'],
  },
  async (request) => {
    if (process.env.FUNCTIONS_EMULATOR !== 'true') {
      throw new HttpsError(
        'failed-precondition',
        'Chức năng này chỉ dùng cho demo trên Firebase Emulator.'
      );
    }

    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Vui lòng đăng nhập để chạy demo.');
    }

    const db = getFirestore();
    const userRef = db.collection('users').doc(uid);
    const settingsDoc = await userRef.collection('settings').doc('checkin').get();
    if (!settingsDoc.exists) {
      throw new HttpsError('not-found', 'Không tìm thấy cấu hình check-in của tài khoản.');
    }

    const result = await processSingleUserCheckIn({
      db,
      userRef,
      settingsDoc,
      now: new Date(),
      emailService: new EmailService(),
      ignorePreviousAlerts: true,
    });

    return {
      action: result.action,
      status: result.status ?? null,
      recipientsCount: result.recipientsCount ?? 0,
    };
  }
);
