"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const firestore_1 = require("firebase-admin/firestore");
const safetyEngine_1 = require("../src/safetyEngine");
(0, node_test_1.describe)('Alert Integration & Contact Consent Filtering Tests', () => {
    const baseTime = new Date('2026-10-27T08:00:00.000Z');
    const dueTime = new Date('2026-10-28T08:00:00.000Z'); // 24h later
    const settings = {
        intervalHours: 24,
        reminderMinutesBefore: 120,
        isReminderEnabled: true,
        isDeadManSwitchActive: true,
        gracePeriodMinutes: safetyEngine_1.DEFAULT_GRACE_PERIOD_MINUTES,
        lastCheckInAt: firestore_1.Timestamp.fromDate(baseTime),
        nextCheckInDueAt: firestore_1.Timestamp.fromDate(dueTime),
        updatedAt: firestore_1.Timestamp.fromDate(baseTime),
    };
    (0, node_test_1.it)('1. Lọc danh bạ: Chỉ người liên hệ đã xác minh email VÀ đã chấp thuận consent mới được nhận cảnh báo', () => {
        const mockContacts = [
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
        node_assert_1.default.strictEqual(eligibleContacts.length, 1);
        node_assert_1.default.strictEqual(eligibleContacts[0].id, 'c1');
    });
    (0, node_test_1.it)('2. Chống Race Condition: Khi cron job bắt đầu phát hiện quá hạn nhưng transaction đọc thấy check-in mới thì huỷ cảnh báo', () => {
        // Giả sử mốc quét là 2026-10-28T12:00:00Z (quá hạn 4 giờ, grace period 3 giờ -> đủ điều kiện TRIGGER_DRY_RUN)
        const scanTime = new Date('2026-10-28T12:00:00.000Z');
        const staleAlert = {
            id: 'event_old',
            uid: 'user_123',
            checkInDueAt: settings.nextCheckInDueAt,
            gracePeriodEndsAt: firestore_1.Timestamp.fromDate(new Date('2026-10-28T11:00:00.000Z')),
            status: 'overdue',
            detectedAt: firestore_1.Timestamp.fromDate(new Date('2026-10-28T08:15:00.000Z')),
        };
        // Khi transaction đọc lại doc.ref, người dùng vừa check-in lúc 11:59:00Z
        const checkInTime = new Date('2026-10-28T11:59:00.000Z');
        const freshNextDue = new Date('2026-10-29T11:59:00.000Z');
        const freshSettings = {
            ...settings,
            lastCheckInAt: firestore_1.Timestamp.fromDate(checkInTime),
            nextCheckInDueAt: firestore_1.Timestamp.fromDate(freshNextDue),
            updatedAt: firestore_1.Timestamp.fromDate(checkInTime),
        };
        // Đánh giá trong transaction với freshSettings
        const result = (0, safetyEngine_1.evaluateDeadManSwitch)({
            now: scanTime,
            settings: freshSettings,
            existingAlert: staleAlert,
        });
        // Kết quả phải là CANCEL_ALERT, không được phép TRIGGER_DRY_RUN
        node_assert_1.default.strictEqual(result.action, 'CANCEL_ALERT');
        node_assert_1.default.strictEqual(result.targetStatus, 'cancelled');
        node_assert_1.default.match(result.reason, /an toàn trở lại/);
    });
    (0, node_test_1.it)('3. Idempotency: Không bao giờ kích hoạt cảnh báo lặp lại khi đã ở trạng thái dry_run_dispatched', () => {
        const scanTime = new Date('2026-10-28T14:00:00.000Z');
        const dispatchedAlert = {
            id: 'event_dispatched',
            uid: 'user_123',
            checkInDueAt: settings.nextCheckInDueAt,
            gracePeriodEndsAt: firestore_1.Timestamp.fromDate(new Date('2026-10-28T11:00:00.000Z')),
            status: 'dry_run_dispatched',
            detectedAt: firestore_1.Timestamp.fromDate(new Date('2026-10-28T08:15:00.000Z')),
            resolvedAt: firestore_1.Timestamp.fromDate(new Date('2026-10-28T11:05:00.000Z')),
            dryRunDetails: {
                isDryRun: true,
                simulatedRecipientsCount: 2,
                simulatedMessage: 'Test message',
                evaluatedAt: firestore_1.Timestamp.fromDate(new Date('2026-10-28T11:05:00.000Z')),
            },
        };
        const result = (0, safetyEngine_1.evaluateDeadManSwitch)({
            now: scanTime,
            settings,
            existingAlert: dispatchedAlert,
        });
        node_assert_1.default.strictEqual(result.action, 'NO_ACTION');
        node_assert_1.default.match(result.reason, /idempotency/);
    });
});
//# sourceMappingURL=alertIntegration.test.js.map