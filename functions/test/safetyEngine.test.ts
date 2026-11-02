import { describe, it } from 'node:test';
import assert from 'node:assert';
import { Timestamp } from 'firebase-admin/firestore';
import { evaluateDeadManSwitch, DEFAULT_GRACE_PERIOD_MINUTES } from '../src/safetyEngine';
import { CheckInSettings, AlertEvent } from '../src/types';

describe('Dead Man\'s Switch Safety Engine Tests', () => {
  const baseTime = new Date('2025-05-20T10:00:00.000Z');
  const dueTime = new Date('2025-05-21T10:00:00.000Z'); // 24 giờ sau

  const defaultSettings: CheckInSettings = {
    intervalHours: 24,
    reminderMinutesBefore: 120,
    isReminderEnabled: true,
    isDeadManSwitchActive: true,
    gracePeriodMinutes: DEFAULT_GRACE_PERIOD_MINUTES, // 180 phút
    lastCheckInAt: Timestamp.fromDate(baseTime),
    nextCheckInDueAt: Timestamp.fromDate(dueTime),
    updatedAt: Timestamp.fromDate(baseTime),
  };

  it('1. Người dùng còn hạn check-in -> Không có hành động nào (NO_ACTION)', () => {
    // 5 giờ trước khi đến hạn
    const evalTime = new Date('2025-05-21T05:00:00.000Z');
    const result = evaluateDeadManSwitch({
      now: evalTime,
      settings: defaultSettings,
    });

    assert.strictEqual(result.action, 'NO_ACTION');
    assert.match(result.reason, /trong thời hạn/);
  });

  it('2. Quá hạn nhưng vẫn trong thời gian gia hạn (Grace Period) -> Bắt đầu đếm ngược gia hạn (START_GRACE_PERIOD)', () => {
    // Quá hạn 30 phút (Hạn là 10:00, giờ là 10:30, ngưỡng gia hạn đến 13:00)
    const evalTime = new Date('2025-05-21T10:30:00.000Z');
    const result = evaluateDeadManSwitch({
      now: evalTime,
      settings: defaultSettings,
    });

    assert.strictEqual(result.action, 'START_GRACE_PERIOD');
    assert.strictEqual(result.targetStatus, 'overdue');
    assert.ok(result.gracePeriodEndsAt);
    assert.strictEqual(
      result.gracePeriodEndsAt.toISOString(),
      new Date('2025-05-21T13:00:00.000Z').toISOString()
    );
  });

  it('3. Đã có sự kiện overdue và đang trong grace period -> Không gửi cảnh báo (NO_ACTION)', () => {
    // Quá hạn 60 phút
    const evalTime = new Date('2025-05-21T11:00:00.000Z');
    const graceEndsAt = new Date('2025-05-21T13:00:00.000Z');

    const existingAlert: AlertEvent = {
      id: 'event_1',
      uid: 'user_123',
      checkInDueAt: defaultSettings.nextCheckInDueAt!,
      gracePeriodEndsAt: Timestamp.fromDate(graceEndsAt),
      status: 'overdue',
      detectedAt: Timestamp.fromDate(new Date('2025-05-21T10:05:00.000Z')),
    };

    const result = evaluateDeadManSwitch({
      now: evalTime,
      settings: defaultSettings,
      existingAlert,
    });

    assert.strictEqual(result.action, 'NO_ACTION');
    assert.match(result.reason, /trong thời gian gia hạn/);
  });

  it('4. Hết thời gian gia hạn (Grace Period) -> Kích hoạt Dry-Run cảnh báo (TRIGGER_DRY_RUN)', () => {
    // Thời điểm 13:05 (quá hạn gia hạn 5 phút)
    const evalTime = new Date('2025-05-21T13:05:00.000Z');
    const graceEndsAt = new Date('2025-05-21T13:00:00.000Z');

    const existingAlert: AlertEvent = {
      id: 'event_1',
      uid: 'user_123',
      checkInDueAt: defaultSettings.nextCheckInDueAt!,
      gracePeriodEndsAt: Timestamp.fromDate(graceEndsAt),
      status: 'overdue',
      detectedAt: Timestamp.fromDate(new Date('2025-05-21T10:05:00.000Z')),
    };

    const result = evaluateDeadManSwitch({
      now: evalTime,
      settings: defaultSettings,
      existingAlert,
    });

    assert.strictEqual(result.action, 'TRIGGER_DRY_RUN');
    assert.strictEqual(result.targetStatus, 'dry_run_dispatched');
  });

  it('5. Người dùng check-in mới trước khi kích hoạt -> Tự động huỷ cảnh báo (CANCEL_ALERT)', () => {
    // Đang trong grace period lúc 11:00, người dùng mở app bấm check-in lúc 11:05
    const checkInNewTime = new Date('2025-05-21T11:05:00.000Z');
    const newDueTime = new Date('2025-05-22T11:05:00.000Z');

    const updatedSettings: CheckInSettings = {
      ...defaultSettings,
      lastCheckInAt: Timestamp.fromDate(checkInNewTime),
      nextCheckInDueAt: Timestamp.fromDate(newDueTime),
    };

    const existingAlert: AlertEvent = {
      id: 'event_1',
      uid: 'user_123',
      checkInDueAt: defaultSettings.nextCheckInDueAt!, // Mốc hạn cũ lúc 21/05 10:00
      gracePeriodEndsAt: Timestamp.fromDate(new Date('2025-05-21T13:00:00.000Z')),
      status: 'overdue',
      detectedAt: Timestamp.fromDate(new Date('2025-05-21T10:05:00.000Z')),
    };

    // Máy chủ quét định kỳ lúc 11:15
    const evalTime = new Date('2025-05-21T11:15:00.000Z');
    const result = evaluateDeadManSwitch({
      now: evalTime,
      settings: updatedSettings,
      existingAlert,
    });

    assert.strictEqual(result.action, 'CANCEL_ALERT');
    assert.strictEqual(result.targetStatus, 'cancelled');
    assert.match(result.reason, /check-in an toàn trở lại/);
  });

  it('6. Cảnh báo đã được xử lý (dry_run_dispatched) -> Không gửi lặp (Idempotency check)', () => {
    // Máy chủ quét lại lúc 14:00 sau khi dry-run đã gửi lúc 13:05
    const evalTime = new Date('2025-05-21T14:00:00.000Z');
    const existingAlert: AlertEvent = {
      id: 'event_1',
      uid: 'user_123',
      checkInDueAt: defaultSettings.nextCheckInDueAt!,
      gracePeriodEndsAt: Timestamp.fromDate(new Date('2025-05-21T13:00:00.000Z')),
      status: 'dry_run_dispatched',
      detectedAt: Timestamp.fromDate(new Date('2025-05-21T10:05:00.000Z')),
    };

    const result = evaluateDeadManSwitch({
      now: evalTime,
      settings: defaultSettings,
      existingAlert,
    });

    assert.strictEqual(result.action, 'NO_ACTION');
    assert.match(result.reason, /đã được xử lý trước đó/);
  });

  it('7. Thiếu dữ liệu thời gian nextCheckInDueAt -> Không làm gì (An toàn lỗi)', () => {
    const corruptSettings: CheckInSettings = {
      ...defaultSettings,
      nextCheckInDueAt: null,
    };

    const result = evaluateDeadManSwitch({
      now: new Date('2025-05-21T12:00:00.000Z'),
      settings: corruptSettings,
    });

    assert.strictEqual(result.action, 'NO_ACTION');
    assert.match(result.reason, /Chưa có mốc thời gian/);
  });

  it('8. Người dùng đã tắt tính năng Dead Man\'s Switch -> Bỏ qua hoàn toàn', () => {
    const disabledSettings: CheckInSettings = {
      ...defaultSettings,
      isDeadManSwitchActive: false,
    };

    const result = evaluateDeadManSwitch({
      now: new Date('2025-05-21T15:00:00.000Z'),
      settings: disabledSettings,
    });

    assert.strictEqual(result.action, 'NO_ACTION');
    assert.match(result.reason, /đang bị tắt bởi người dùng/);
  });

  it('9. Hai tài khoản độc lập không ảnh hưởng lẫn nhau', () => {
    const userASettings: CheckInSettings = {
      ...defaultSettings,
      nextCheckInDueAt: Timestamp.fromDate(new Date('2025-05-21T08:00:00.000Z')), // Đã quá hạn
    };

    const userBSettings: CheckInSettings = {
      ...defaultSettings,
      nextCheckInDueAt: Timestamp.fromDate(new Date('2025-05-21T20:00:00.000Z')), // Vẫn còn hạn
    };

    const now = new Date('2025-05-21T10:00:00.000Z');

    const evalA = evaluateDeadManSwitch({ now, settings: userASettings });
    const evalB = evaluateDeadManSwitch({ now, settings: userBSettings });

    assert.strictEqual(evalA.action, 'START_GRACE_PERIOD');
    assert.strictEqual(evalB.action, 'NO_ACTION');
  });

  it('10. Sự kiện cũ đã cancelled và người dùng tiếp tục quá hạn ở chu kỳ tiếp theo -> Bắt đầu chu kỳ mới đúng', () => {
    // Sự kiện cũ của ngày hôm trước đã bị huỷ
    const oldCancelledAlert: AlertEvent = {
      id: 'event_old',
      uid: 'user_123',
      checkInDueAt: Timestamp.fromDate(new Date('2025-05-20T10:00:00.000Z')),
      gracePeriodEndsAt: Timestamp.fromDate(new Date('2025-05-20T13:00:00.000Z')),
      status: 'cancelled',
      detectedAt: Timestamp.fromDate(new Date('2025-05-20T10:05:00.000Z')),
    };

    // Bây giờ quá hạn ở mốc 21/05 10:00, thời điểm hiện tại 10:15
    const now = new Date('2025-05-21T10:15:00.000Z');
    const result = evaluateDeadManSwitch({
      now,
      settings: defaultSettings,
      existingAlert: oldCancelledAlert,
    });

    assert.strictEqual(result.action, 'START_GRACE_PERIOD');
    assert.strictEqual(result.targetStatus, 'overdue');
  });
});
