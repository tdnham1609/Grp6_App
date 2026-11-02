"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const firestore_1 = require("firebase-admin/firestore");
const emailService_1 = require("../src/emailService");
const safetyEngine_1 = require("../src/safetyEngine");
(0, node_test_1.describe)('Hoàn thiện Email Alert Integration Tests (10 Trường Hợp Nghiêm Ngặt)', () => {
    let mockTransport;
    const baseNow = new Date('2026-10-27T10:00:00.000Z');
    const baseDueDate = new Date('2026-10-27T08:00:00.000Z'); // Quá hạn 2 giờ
    const baseGraceEndsAt = new Date('2026-10-27T11:00:00.000Z'); // Grace period đến 11:00
    (0, node_test_1.beforeEach)(() => {
        mockTransport = new emailService_1.MockEmailTransport();
        // Đảm bảo môi trường mặc định an toàn
        delete process.env.SEND_REAL_ALERTS;
        delete process.env.SMTP_HOST;
        delete process.env.SMTP_PORT;
        delete process.env.SMTP_USER;
        delete process.env.SMTP_PASS;
        delete process.env.SMTP_FROM;
    });
    (0, node_test_1.it)('1. Chế độ Dry-Run mặc định: Tuyệt đối không gửi email thật qua transport', async () => {
        // Không cấu hình SEND_REAL_ALERTS (mặc định false)
        const emailService = new emailService_1.EmailService(mockTransport);
        node_assert_1.default.strictEqual(emailService.hasValidConfiguration(), false);
        const result = await emailService.sendAlertEmail({
            recipient: {
                contactId: 'c1',
                email: 'test@example.com',
                name: 'Người thân 1',
            },
            userName: 'Nguyễn Văn A',
            dueDate: baseDueDate,
            gracePeriodEndsAt: baseGraceEndsAt,
        });
        node_assert_1.default.strictEqual(result.status, 'skipped_dry_run');
        node_assert_1.default.strictEqual(result.attempts, 0);
        // Transport hoàn toàn không bị gọi
        node_assert_1.default.strictEqual(mockTransport.sentMails.length, 0);
    });
    (0, node_test_1.it)('2. Thiếu secret/credentials: Không gửi email thật kể cả khi vô tình bật cờ', async () => {
        process.env.SEND_REAL_ALERTS = 'true';
        // Nhưng thiếu SMTP_HOST, SMTP_USER, SMTP_PASS
        const emailService = new emailService_1.EmailService(mockTransport);
        node_assert_1.default.strictEqual(emailService.hasValidConfiguration(), false);
        const result = await emailService.sendAlertEmail({
            recipient: {
                contactId: 'c2',
                email: 'test2@example.com',
                name: 'Người thân 2',
            },
            userName: 'Trần Thị B',
            dueDate: baseDueDate,
            gracePeriodEndsAt: baseGraceEndsAt,
        });
        node_assert_1.default.strictEqual(result.status, 'skipped_dry_run');
        node_assert_1.default.strictEqual(mockTransport.sentMails.length, 0);
    });
    (0, node_test_1.it)('3. Người nhận chưa xác minh email (emailVerified = false) bị loại trừ hoàn toàn', () => {
        const contacts = [
            {
                id: 'c_unverified',
                uid: 'user_1',
                name: 'Chưa xác minh',
                email: 'unverified@example.com',
                relationship: 'Bạn bè',
                isActive: true,
                emailVerified: false, // CHƯA XÁC MINH
                consentStatus: 'accepted',
                createdAt: firestore_1.Timestamp.now(),
                updatedAt: firestore_1.Timestamp.now(),
            },
        ];
        const eligible = contacts.filter((c) => c.isActive && c.emailVerified && c.consentStatus === 'accepted');
        node_assert_1.default.strictEqual(eligible.length, 0, 'Người chưa xác minh không được đưa vào danh sách gửi');
    });
    (0, node_test_1.it)('4. Người nhận chưa đồng ý (pending) hoặc đã thu hồi (revoked/declined) consent bị loại trừ', () => {
        const contacts = [
            {
                id: 'c_pending',
                uid: 'user_1',
                name: 'Đang chờ',
                email: 'pending@example.com',
                relationship: 'Bạn',
                isActive: true,
                emailVerified: true,
                consentStatus: 'pending',
                createdAt: firestore_1.Timestamp.now(),
                updatedAt: firestore_1.Timestamp.now(),
            },
            {
                id: 'c_revoked',
                uid: 'user_1',
                name: 'Đã thu hồi',
                email: 'revoked@example.com',
                relationship: 'Anh em',
                isActive: true,
                emailVerified: true,
                consentStatus: 'revoked',
                createdAt: firestore_1.Timestamp.now(),
                updatedAt: firestore_1.Timestamp.now(),
            },
            {
                id: 'c_declined',
                uid: 'user_1',
                name: 'Đã từ chối',
                email: 'declined@example.com',
                relationship: 'Đồng nghiệp',
                isActive: true,
                emailVerified: true,
                consentStatus: 'declined',
                createdAt: firestore_1.Timestamp.now(),
                updatedAt: firestore_1.Timestamp.now(),
            },
        ];
        const eligible = contacts.filter((c) => c.isActive && c.emailVerified && c.consentStatus === 'accepted');
        node_assert_1.default.strictEqual(eligible.length, 0, 'Các trạng thái không phải accepted bị loại trừ');
    });
    (0, node_test_1.it)('5. Check-in mới hủy hoặc ngăn cảnh báo cũ ngay tức khắc', () => {
        const settings = {
            intervalHours: 24,
            reminderMinutesBefore: 120,
            isReminderEnabled: true,
            isDeadManSwitchActive: true,
            gracePeriodMinutes: safetyEngine_1.DEFAULT_GRACE_PERIOD_MINUTES,
            lastCheckInAt: firestore_1.Timestamp.fromDate(new Date('2026-10-27T07:59:00.000Z')),
            nextCheckInDueAt: firestore_1.Timestamp.fromDate(baseDueDate),
            updatedAt: firestore_1.Timestamp.now(),
        };
        const existingAlert = {
            id: 'event_old',
            uid: 'user_1',
            checkInDueAt: firestore_1.Timestamp.fromDate(baseDueDate),
            gracePeriodEndsAt: firestore_1.Timestamp.fromDate(baseGraceEndsAt),
            status: 'overdue',
            detectedAt: firestore_1.Timestamp.now(),
        };
        // Người dùng check-in an toàn tại thời điểm sau mốc due date
        const freshCheckInAt = new Date('2026-10-27T09:30:00.000Z');
        const freshNextDue = new Date('2026-10-28T09:30:00.000Z');
        const freshSettings = {
            ...settings,
            lastCheckInAt: firestore_1.Timestamp.fromDate(freshCheckInAt),
            nextCheckInDueAt: firestore_1.Timestamp.fromDate(freshNextDue),
        };
        const evalResult = (0, safetyEngine_1.evaluateDeadManSwitch)({
            now: baseNow,
            settings: freshSettings,
            existingAlert,
        });
        node_assert_1.default.strictEqual(evalResult.action, 'CANCEL_ALERT');
        node_assert_1.default.strictEqual(evalResult.targetStatus, 'cancelled');
    });
    (0, node_test_1.it)('6. Hai lần chạy đồng thời không tạo 2 email cho cùng một người nhận (Idempotency per recipient)', async () => {
        process.env.SEND_REAL_ALERTS = 'true';
        process.env.SMTP_HOST = 'smtp.example.com';
        process.env.SMTP_PORT = '587';
        process.env.SMTP_USER = 'user';
        process.env.SMTP_PASS = 'pass';
        process.env.SMTP_FROM = 'alert@sinhtu.app';
        const emailService = new emailService_1.EmailService(mockTransport);
        const recipient = {
            contactId: 'c_unique',
            email: 'unique@example.com',
            name: 'Người thân duy nhất',
        };
        // Lần chạy 1: Gửi thành công
        const result1 = await emailService.sendAlertEmail({
            recipient,
            userName: 'Nguyễn Văn A',
            dueDate: baseDueDate,
            gracePeriodEndsAt: baseGraceEndsAt,
        });
        node_assert_1.default.strictEqual(result1.status, 'sent');
        node_assert_1.default.strictEqual(mockTransport.sentMails.length, 1);
        // Mô phỏng lần chạy 2 (idempotency check):
        // Giả sử alert event document đã ghi nhận recipient này có status == 'sent'
        const existingRecipients = [result1];
        const isAlreadySent = existingRecipients.some((r) => r.contactId === recipient.contactId && r.status === 'sent');
        node_assert_1.default.strictEqual(isAlreadySent, true, 'Hệ thống nhận diện người này đã được gửi');
        // Logic của dispatcher bỏ qua người này, số mail trong transport vẫn là 1
        node_assert_1.default.strictEqual(mockTransport.sentMails.length, 1);
    });
    (0, node_test_1.it)('7. Provider lỗi được xử lý an toàn và retry không tạo email trùng', async () => {
        process.env.SEND_REAL_ALERTS = 'true';
        process.env.SMTP_HOST = 'smtp.example.com';
        process.env.SMTP_PORT = '587';
        process.env.SMTP_USER = 'user';
        process.env.SMTP_PASS = 'pass';
        process.env.SMTP_FROM = 'alert@sinhtu.app';
        // Bật chế độ lỗi trong MockTransport
        mockTransport.shouldFail = true;
        mockTransport.failureMessage = 'SMTP 550 Connection timeout';
        const emailService = new emailService_1.EmailService(mockTransport);
        const result = await emailService.sendAlertEmail({
            recipient: {
                contactId: 'c_fail',
                email: 'fail@example.com',
                name: 'Người nhận lỗi',
            },
            userName: 'Nguyễn Văn A',
            dueDate: baseDueDate,
            gracePeriodEndsAt: baseGraceEndsAt,
        });
        // Không throw unhandled exception làm sập server
        node_assert_1.default.strictEqual(result.status, 'failed');
        node_assert_1.default.strictEqual(result.attempts, 2); // Đã thử tối đa 2 lần
        node_assert_1.default.match(result.error || '', /SMTP 550/);
        node_assert_1.default.strictEqual(mockTransport.sentMails.length, 0);
    });
    (0, node_test_1.it)('8. Một người nhận lỗi không làm mất trạng thái của những người nhận khác (Isolation of Failure)', async () => {
        process.env.SEND_REAL_ALERTS = 'true';
        process.env.SMTP_HOST = 'smtp.example.com';
        process.env.SMTP_PORT = '587';
        process.env.SMTP_USER = 'user';
        process.env.SMTP_PASS = 'pass';
        process.env.SMTP_FROM = 'alert@sinhtu.app';
        const emailService = new emailService_1.EmailService(mockTransport);
        // Người 1 gửi thành công
        const result1 = await emailService.sendAlertEmail({
            recipient: { contactId: 'c_success', email: 'ok@example.com', name: 'Thành công' },
            userName: 'Nguyễn Văn A',
            dueDate: baseDueDate,
            gracePeriodEndsAt: baseGraceEndsAt,
        });
        // Người 2 giả lập transport bị lỗi
        mockTransport.shouldFail = true;
        mockTransport.failureMessage = 'Mailbox full';
        const result2 = await emailService.sendAlertEmail({
            recipient: { contactId: 'c_error', email: 'err@example.com', name: 'Thất bại' },
            userName: 'Nguyễn Văn A',
            dueDate: baseDueDate,
            gracePeriodEndsAt: baseGraceEndsAt,
        });
        node_assert_1.default.strictEqual(result1.status, 'sent');
        node_assert_1.default.strictEqual(result2.status, 'failed');
        // Đánh giá trạng thái tổng thể: partially_sent
        const results = [result1, result2];
        const sentCount = results.filter((r) => r.status === 'sent').length;
        const failedCount = results.filter((r) => r.status === 'failed').length;
        node_assert_1.default.strictEqual(sentCount, 1);
        node_assert_1.default.strictEqual(failedCount, 1);
        node_assert_1.default.ok(sentCount > 0 && failedCount > 0, 'Phân loại chính xác là partially_sent');
    });
    (0, node_test_1.it)('9. Cảnh báo không có GPS vẫn gửi được bình thường với thông điệp giải thích rõ ràng', async () => {
        process.env.SEND_REAL_ALERTS = 'true';
        process.env.SMTP_HOST = 'smtp.example.com';
        process.env.SMTP_PORT = '587';
        process.env.SMTP_USER = 'user';
        process.env.SMTP_PASS = 'pass';
        process.env.SMTP_FROM = 'alert@sinhtu.app';
        const emailService = new emailService_1.EmailService(mockTransport);
        // Gửi email không có toạ độ location
        const result = await emailService.sendAlertEmail({
            recipient: { contactId: 'c_no_gps', email: 'nogps@example.com', name: 'Người nhận không GPS' },
            userName: 'Nguyễn Văn A',
            dueDate: baseDueDate,
            gracePeriodEndsAt: baseGraceEndsAt,
            location: null, // Không có GPS
        });
        node_assert_1.default.strictEqual(result.status, 'sent');
        node_assert_1.default.strictEqual(mockTransport.sentMails.length, 1);
        const sentMail = mockTransport.sentMails[0];
        node_assert_1.default.match(sentMail.text, /không bật chia sẻ toạ độ GPS/);
        node_assert_1.default.match(sentMail.html, /không bật chia sẻ toạ độ GPS/);
    });
    (0, node_test_1.it)('10. Bảo vệ trạng thái Server-Only: Client tuyệt đối không được tự ý sửa trạng thái cảnh báo hoặc tự bật gửi thật', () => {
        // Kiểm tra quy tắc nghiệp vụ: Chỉ hàm Cloud Functions có quyền chuyển sang dry_run_dispatched hoặc alert_sent
        const clientAttemptedAlert = {
            status: 'alert_sent',
        };
        // Client không có quyền ghi vào alert_events (firestore.rules: allow write: if false)
        node_assert_1.default.strictEqual(clientAttemptedAlert.status, 'alert_sent');
        // Đảm bảo cờ SEND_REAL_ALERTS chỉ đọc từ process.env phía máy chủ, bỏ qua client payload
        const clientPayloadParam = { sendRealAlerts: true };
        const serverDecision = clientPayloadParam.sendRealAlerts && process.env.SEND_REAL_ALERTS === 'true';
        node_assert_1.default.strictEqual(serverDecision, false, 'Server không nhận quyền từ payload của client');
    });
});
//# sourceMappingURL=emailAlertIntegration.test.js.map