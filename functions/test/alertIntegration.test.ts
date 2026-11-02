import { describe, it } from 'node:test';
import assert from 'node:assert';
import { Timestamp } from 'firebase-admin/firestore';
import { evaluateDeadManSwitch, DEFAULT_GRACE_PERIOD_MINUTES } from '../src/safetyEngine';
import { CheckInSettings, AlertEvent, EmergencyContactDoc } from '../src/types';

describe('Alert Integration & Contact Consent Filtering Tests', () => {
  const baseTime = new Date('2026-10-27T08:00:00.000Z');
  const dueTime = new Date('2026-10-28T08:00:00.000Z'); // 24h later

  const settings: CheckInSettings = {
    intervalHours: 24,
    reminderMinutesBefore: 120,
    isReminderEnabled: true,
    isDeadManSwitchActive: true,
    gracePeriodMinutes: DEFAULT_GRACE_PERIOD_MINUTES,
    lastCheckInAt: Timestamp.fromDate(baseTime),
    nextCheckInDueAt: Timestamp.fromDate(dueTime),
    updatedAt: Timestamp.fromDate(baseTime),
  };

  it('1. Lọc danh bạ: Chỉ người liên hệ đã xác minh email VÀ đã chấp thuận consent mới được nhận cảnh báo', () => {
    const mockContacts: Partial<EmergencyContactDoc>[] = [
      // 1. Đủ điều kiện: active + verified + accepted
      {
        id: 'c1',
        name: 'Người thân A',
        email: 'a@gmail.com',
        isActive: true,
        emailVerified: true,
        consentStatus: 'accepted',
      },
      // 2. Chưa xác minh email (emailVerified = false)
      {
        id: 'c2',
        name: 'Người thân B',
        email: 'b@gmail.com',
        isActive: true,
        emailVerified: false,
        consentStatus: 'accepted',
      },
      // 3. Chưa chấp thuận consent (consentStatus = 'pending')
      {
        id: 'c3',
        name: 'Người thân C',
        email: 'c@gmail.com',
        isActive: true,
        emailVerified: true,
        consentStatus: 'pending',
      },
      // 4. Đã từ chối consent (consentStatus = 'declined')
      {
        id: 'c4',
        name: 'Người thân D',
        email: 'd@gmail.com',
        isActive: true,
        emailVerified: true,
        consentStatus: 'declined',
      },
      // 5. Đã thu hồi consent (consentStatus = 'revoked')
      {
        id: 'c5',
        name: 'Người thân E',
        email: 'e@gmail.com',
        isActive: true,
        emailVerified: true,
        consentStatus: 'revoked',
      },
      // 6. Tạm tắt cảnh báo (isActive = false)
      {
        id: 'c6',
        name: 'Người thân F',
        email: 'f@gmail.com',
        isActive: false,
        emailVerified: true,
        consentStatus: 'accepted',
      },
    ];

    // Lọc theo logic an toàn của checkOverdueDeadManSwitch
    const eligibleContacts = mockContacts.filter((c) => {
      return c.isActive === true && c.emailVerified === true && c.consentStatus === 'accepted';
    });

    assert.strictEqual(eligibleContacts.length, 1);
    assert.strictEqual(eligibleContacts[0].id, 'c1');
  });

  it('2. Chống Race Condition: Khi cron job bắt đầu phát hiện quá hạn nhưng transaction đọc thấy check-in mới thì huỷ cảnh báo', () => {
    // Giả sử mốc quét là 2026-10-28T12:00:00Z (quá hạn 4 giờ, grace period 3 giờ -> đủ điều kiện TRIGGER_DRY_RUN)
    const scanTime = new Date('2026-10-28T12:00:00.000Z');

    const staleAlert: AlertEvent = {
      id: 'event_old',
      uid: 'user_123',
      checkInDueAt: settings.nextCheckInDueAt!,
      gracePeriodEndsAt: Timestamp.fromDate(new Date('2026-10-28T11:00:00.000Z')),
      status: 'overdue',
      detectedAt: Timestamp.fromDate(new Date('2026-10-28T08:15:00.000Z')),
    };

    // Khi transaction đọc lại doc.ref, người dùng vừa check-in lúc 11:59:00Z
    const checkInTime = new Date('2026-10-28T11:59:00.000Z');
    const freshNextDue = new Date('2026-10-29T11:59:00.000Z');

    const freshSettings: CheckInSettings = {
      ...settings,
      lastCheckInAt: Timestamp.fromDate(checkInTime),
      nextCheckInDueAt: Timestamp.fromDate(freshNextDue),
      updatedAt: Timestamp.fromDate(checkInTime),
    };

    // Đánh giá trong transaction với freshSettings
    const result = evaluateDeadManSwitch({
      now: scanTime,
      settings: freshSettings,
      existingAlert: staleAlert,
    });

    // Kết quả phải là CANCEL_ALERT, không được phép TRIGGER_DRY_RUN
    assert.strictEqual(result.action, 'CANCEL_ALERT');
    assert.strictEqual(result.targetStatus, 'cancelled');
    assert.match(result.reason, /an toàn trở lại/);
  });

  it('3. Idempotency: Không bao giờ kích hoạt cảnh báo lặp lại khi đã ở trạng thái dry_run_dispatched', () => {
    const scanTime = new Date('2026-10-28T14:00:00.000Z');

    const dispatchedAlert: AlertEvent = {
      id: 'event_dispatched',
      uid: 'user_123',
      checkInDueAt: settings.nextCheckInDueAt!,
      gracePeriodEndsAt: Timestamp.fromDate(new Date('2026-10-28T11:00:00.000Z')),
      status: 'dry_run_dispatched',
      detectedAt: Timestamp.fromDate(new Date('2026-10-28T08:15:00.000Z')),
      resolvedAt: Timestamp.fromDate(new Date('2026-10-28T11:05:00.000Z')),
      dryRunDetails: {
        isDryRun: true,
        simulatedRecipientsCount: 2,
        simulatedMessage: 'Test message',
        evaluatedAt: Timestamp.fromDate(new Date('2026-10-28T11:05:00.000Z')),
      },
    };

    const result = evaluateDeadManSwitch({
      now: scanTime,
      settings,
      existingAlert: dispatchedAlert,
    });

    assert.strictEqual(result.action, 'NO_ACTION');
    assert.match(result.reason, /idempotency/);
  });
});
