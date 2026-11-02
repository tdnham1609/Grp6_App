"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const firestore_1 = require("firebase-admin/firestore");
const safetyEngine_1 = require("../src/safetyEngine");
(0, node_test_1.describe)('Dead Man\'s Switch Safety Engine Tests', () => {
    const baseTime = new Date('2025-05-20T10:00:00.000Z');
    const dueTime = new Date('2025-05-21T10:00:00.000Z'); // 24 giờ sau
    const defaultSettings = {
        intervalHours: 24,
        reminderMinutesBefore: 120,
        isReminderEnabled: true,
        isDeadManSwitchActive: true,
        gracePeriodMinutes: safetyEngine_1.DEFAULT_GRACE_PERIOD_MINUTES, // 180 phút
        lastCheckInAt: firestore_1.Timestamp.fromDate(baseTime),
        nextCheckInDueAt: firestore_1.Timestamp.fromDate(dueTime),
        updatedAt: firestore_1.Timestamp.fromDate(baseTime),
    };
    (0, node_test_1.it)('1. Người dùng còn hạn check-in -> Không có hành động nào (NO_ACTION)', () => {
        // 5 giờ trước khi đến hạn
        const evalTime = new Date('2025-05-21T05:00:00.000Z');
        const result = (0, safetyEngine_1.evaluateDeadManSwitch)({
            now: evalTime,
            settings: defaultSettings,
        });
        node_assert_1.default.strictEqual(result.action, 'NO_ACTION');
        node_assert_1.default.match(result.reason, /trong thời hạn/);
    });
    (0, node_test_1.it)('2. Quá hạn nhưng vẫn trong thời gian gia hạn (Grace Period) -> Bắt đầu đếm ngược gia hạn (START_GRACE_PERIOD)', () => {
        // Quá hạn 30 phút (Hạn là 10:00, giờ là 10:30, ngưỡng gia hạn đến 13:00)
        const evalTime = new Date('2025-05-21T10:30:00.000Z');
        const result = (0, safetyEngine_1.evaluateDeadManSwitch)({
            now: evalTime,
            settings: defaultSettings,
        });
        node_assert_1.default.strictEqual(result.action, 'START_GRACE_PERIOD');
        node_assert_1.default.strictEqual(result.targetStatus, 'overdue');
        node_assert_1.default.ok(result.gracePeriodEndsAt);
        node_assert_1.default.strictEqual(result.gracePeriodEndsAt.toISOString(), new Date('2025-05-21T13:00:00.000Z').toISOString());
    });
    (0, node_test_1.it)('3. Đã có sự kiện overdue và đang trong grace period -> Không gửi cảnh báo (NO_ACTION)', () => {
        // Quá hạn 60 phút
        const evalTime = new Date('2025-05-21T11:00:00.000Z');
        const graceEndsAt = new Date('2025-05-21T13:00:00.000Z');
        const existingAlert = {
            id: 'event_1',
            uid: 'user_123',
            checkInDueAt: defaultSettings.nextCheckInDueAt,
            gracePeriodEndsAt: firestore_1.Timestamp.fromDate(graceEndsAt),
            status: 'overdue',
            detectedAt: firestore_1.Timestamp.fromDate(new Date('2025-05-21T10:05:00.000Z')),
        };
        const result = (0, safetyEngine_1.evaluateDeadManSwitch)({
            now: evalTime,
            settings: defaultSettings,
            existingAlert,
        });
        node_assert_1.default.strictEqual(result.action, 'NO_ACTION');
        node_assert_1.default.match(result.reason, /trong thời gian gia hạn/);
    });
    (0, node_test_1.it)('4. Hết thời gian gia hạn (Grace Period) -> Kích hoạt Dry-Run cảnh báo (TRIGGER_DRY_RUN)', () => {
        // Thời điểm 13:05 (quá hạn gia hạn 5 phút)
        const evalTime = new Date('2025-05-21T13:05:00.000Z');
        const graceEndsAt = new Date('2025-05-21T13:00:00.000Z');
        const existingAlert = {
            id: 'event_1',
            uid: 'user_123',
            checkInDueAt: defaultSettings.nextCheckInDueAt,
            gracePeriodEndsAt: firestore_1.Timestamp.fromDate(graceEndsAt),
            status: 'overdue',
            detectedAt: firestore_1.Timestamp.fromDate(new Date('2025-05-21T10:05:00.000Z')),
        };
        const result = (0, safetyEngine_1.evaluateDeadManSwitch)({
            now: evalTime,
            settings: defaultSettings,
            existingAlert,
        });
        node_assert_1.default.strictEqual(result.action, 'TRIGGER_DRY_RUN');
        node_assert_1.default.strictEqual(result.targetStatus, 'dry_run_dispatched');
    });
    (0, node_test_1.it)('5. Người dùng check-in mới trước khi kích hoạt -> Tự động huỷ cảnh báo (CANCEL_ALERT)', () => {
        // Đang trong grace period lúc 11:00, người dùng mở app bấm check-in lúc 11:05
        const checkInNewTime = new Date('2025-05-21T11:05:00.000Z');
        const newDueTime = new Date('2025-05-22T11:05:00.000Z');
        const updatedSettings = {
            ...defaultSettings,
            lastCheckInAt: firestore_1.Timestamp.fromDate(checkInNewTime),
            nextCheckInDueAt: firestore_1.Timestamp.fromDate(newDueTime),
        };
        const existingAlert = {
            id: 'event_1',
            uid: 'user_123',
            checkInDueAt: defaultSettings.nextCheckInDueAt, // Mốc hạn cũ lúc 21/05 10:00
            gracePeriodEndsAt: firestore_1.Timestamp.fromDate(new Date('2025-05-21T13:00:00.000Z')),
            status: 'overdue',
            detectedAt: firestore_1.Timestamp.fromDate(new Date('2025-05-21T10:05:00.000Z')),
        };
        // Máy chủ quét định kỳ lúc 11:15
        const evalTime = new Date('2025-05-21T11:15:00.000Z');
        const result = (0, safetyEngine_1.evaluateDeadManSwitch)({
            now: evalTime,
            settings: updatedSettings,
            existingAlert,
        });
        node_assert_1.default.strictEqual(result.action, 'CANCEL_ALERT');
        node_assert_1.default.strictEqual(result.targetStatus, 'cancelled');
        node_assert_1.default.match(result.reason, /check-in an toàn trở lại/);
    });
    (0, node_test_1.it)('6. Cảnh báo đã được xử lý (dry_run_dispatched) -> Không gửi lặp (Idempotency check)', () => {
        // Máy chủ quét lại lúc 14:00 sau khi dry-run đã gửi lúc 13:05
        const evalTime = new Date('2025-05-21T14:00:00.000Z');
        const existingAlert = {
            id: 'event_1',
            uid: 'user_123',
            checkInDueAt: defaultSettings.nextCheckInDueAt,
            gracePeriodEndsAt: firestore_1.Timestamp.fromDate(new Date('2025-05-21T13:00:00.000Z')),
            status: 'dry_run_dispatched',
            detectedAt: firestore_1.Timestamp.fromDate(new Date('2025-05-21T10:05:00.000Z')),
        };
        const result = (0, safetyEngine_1.evaluateDeadManSwitch)({
            now: evalTime,
            settings: defaultSettings,
            existingAlert,
        });
        node_assert_1.default.strictEqual(result.action, 'NO_ACTION');
        node_assert_1.default.match(result.reason, /đã được xử lý trước đó/);
    });
    (0, node_test_1.it)('7. Thiếu dữ liệu thời gian nextCheckInDueAt -> Không làm gì (An toàn lỗi)', () => {
        const corruptSettings = {
            ...defaultSettings,
            nextCheckInDueAt: null,
        };
        const result = (0, safetyEngine_1.evaluateDeadManSwitch)({
            now: new Date('2025-05-21T12:00:00.000Z'),
            settings: corruptSettings,
        });
        node_assert_1.default.strictEqual(result.action, 'NO_ACTION');
        node_assert_1.default.match(result.reason, /Chưa có mốc thời gian/);
    });
    (0, node_test_1.it)('8. Người dùng đã tắt tính năng Dead Man\'s Switch -> Bỏ qua hoàn toàn', () => {
        const disabledSettings = {
            ...defaultSettings,
            isDeadManSwitchActive: false,
        };
        const result = (0, safetyEngine_1.evaluateDeadManSwitch)({
            now: new Date('2025-05-21T15:00:00.000Z'),
            settings: disabledSettings,
        });
        node_assert_1.default.strictEqual(result.action, 'NO_ACTION');
        node_assert_1.default.match(result.reason, /đang bị tắt bởi người dùng/);
    });
    (0, node_test_1.it)('9. Hai tài khoản độc lập không ảnh hưởng lẫn nhau', () => {
        const userASettings = {
            ...defaultSettings,
            nextCheckInDueAt: firestore_1.Timestamp.fromDate(new Date('2025-05-21T08:00:00.000Z')), // Đã quá hạn
        };
        const userBSettings = {
            ...defaultSettings,
            nextCheckInDueAt: firestore_1.Timestamp.fromDate(new Date('2025-05-21T20:00:00.000Z')), // Vẫn còn hạn
        };
        const now = new Date('2025-05-21T10:00:00.000Z');
        const evalA = (0, safetyEngine_1.evaluateDeadManSwitch)({ now, settings: userASettings });
        const evalB = (0, safetyEngine_1.evaluateDeadManSwitch)({ now, settings: userBSettings });
        node_assert_1.default.strictEqual(evalA.action, 'START_GRACE_PERIOD');
        node_assert_1.default.strictEqual(evalB.action, 'NO_ACTION');
    });
    (0, node_test_1.it)('10. Sự kiện cũ đã cancelled và người dùng tiếp tục quá hạn ở chu kỳ tiếp theo -> Bắt đầu chu kỳ mới đúng', () => {
        // Sự kiện cũ của ngày hôm trước đã bị huỷ
        const oldCancelledAlert = {
            id: 'event_old',
            uid: 'user_123',
            checkInDueAt: firestore_1.Timestamp.fromDate(new Date('2025-05-20T10:00:00.000Z')),
            gracePeriodEndsAt: firestore_1.Timestamp.fromDate(new Date('2025-05-20T13:00:00.000Z')),
            status: 'cancelled',
            detectedAt: firestore_1.Timestamp.fromDate(new Date('2025-05-20T10:05:00.000Z')),
        };
        // Bây giờ quá hạn ở mốc 21/05 10:00, thời điểm hiện tại 10:15
        const now = new Date('2025-05-21T10:15:00.000Z');
        const result = (0, safetyEngine_1.evaluateDeadManSwitch)({
            now,
            settings: defaultSettings,
            existingAlert: oldCancelledAlert,
        });
        node_assert_1.default.strictEqual(result.action, 'START_GRACE_PERIOD');
        node_assert_1.default.strictEqual(result.targetStatus, 'overdue');
    });
});
//# sourceMappingURL=safetyEngine.test.js.map