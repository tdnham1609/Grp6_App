"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const assert = __importStar(require("node:assert"));
const firestore_1 = require("firebase-admin/firestore");
const verificationEngine_1 = require("../src/verificationEngine");
(0, node_test_1.describe)('Contact Verification & Opt-in Consent Tests', () => {
    const baseDate = new Date('2026-10-26T10:00:00.000Z');
    function createMockContact(overrides) {
        return {
            id: 'contact_abc123',
            uid: 'user_xyz789',
            name: 'Nguyễn Văn Người Thân',
            email: 'nguoithan@gmail.com',
            phoneNumber: '0987654321',
            relationship: 'Bố mẹ',
            emailVerified: false,
            consentStatus: 'pending',
            isActive: true,
            createdAt: firestore_1.Timestamp.fromDate(baseDate),
            updatedAt: firestore_1.Timestamp.fromDate(baseDate),
            ...overrides,
        };
    }
    function createMockToken(overrides) {
        const rawToken = 'test_raw_token_32_bytes_super_secure';
        const expiresAt = new Date(baseDate.getTime() + verificationEngine_1.TOKEN_LIFETIME_MS);
        return {
            tokenHash: (0, verificationEngine_1.hashToken)(rawToken),
            uid: 'user_xyz789',
            contactId: 'contact_abc123',
            email: 'nguoithan@gmail.com',
            contactName: 'Nguyễn Văn Người Thân',
            userDisplayName: 'Chủ Tài Khoản',
            status: 'pending',
            attempts: 0,
            maxAttempts: verificationEngine_1.MAX_TOKEN_ATTEMPTS,
            createdAt: firestore_1.Timestamp.fromDate(baseDate),
            expiresAt: firestore_1.Timestamp.fromDate(expiresAt),
            usedAt: null,
            lastAttemptAt: null,
            ...overrides,
        };
    }
    (0, node_test_1.it)('1. Tạo raw token ngẫu nhiên và mã băm SHA-256 an toàn', () => {
        const raw1 = (0, verificationEngine_1.generateRawToken)();
        const raw2 = (0, verificationEngine_1.generateRawToken)();
        assert.notStrictEqual(raw1, raw2);
        assert.strictEqual(raw1.length, 64); // 32 bytes hex = 64 characters
        const hash1 = (0, verificationEngine_1.hashToken)(raw1);
        const hash2 = (0, verificationEngine_1.hashToken)(raw1);
        assert.strictEqual(hash1, hash2, 'Hash của cùng token phải giống nhau');
        assert.notStrictEqual(hash1, raw1, 'Hash không được trùng với raw token');
    });
    (0, node_test_1.it)('2. Token hợp lệ -> VALID', () => {
        const tokenDoc = createMockToken();
        const contactDoc = createMockContact();
        const result = (0, verificationEngine_1.validateVerificationToken)({
            tokenDoc,
            contactDoc,
            now: new Date('2026-10-26T12:00:00.000Z'), // 2 giờ sau khi tạo (vẫn trong hạn 24h)
        });
        assert.strictEqual(result.isValid, true);
        assert.strictEqual(result.code, 'VALID');
    });
    (0, node_test_1.it)('3. Token hết hạn (> 24 giờ) -> EXPIRED', () => {
        const tokenDoc = createMockToken();
        const contactDoc = createMockContact();
        // 25 giờ sau khi tạo
        const expiredTime = new Date(baseDate.getTime() + 25 * 60 * 60 * 1000);
        const result = (0, verificationEngine_1.validateVerificationToken)({
            tokenDoc,
            contactDoc,
            now: expiredTime,
        });
        assert.strictEqual(result.isValid, false);
        assert.strictEqual(result.code, 'EXPIRED');
        assert.strictEqual(result.shouldMarkExpired, true);
    });
    (0, node_test_1.it)('4. Token đã sử dụng -> ALREADY_USED (Chống Replay Attack)', () => {
        const tokenDoc = createMockToken({
            status: 'used',
            usedAt: firestore_1.Timestamp.fromDate(new Date('2026-10-26T11:00:00.000Z')),
        });
        const contactDoc = createMockContact();
        const result = (0, verificationEngine_1.validateVerificationToken)({
            tokenDoc,
            contactDoc,
            now: new Date('2026-10-26T12:00:00.000Z'),
        });
        assert.strictEqual(result.isValid, false);
        assert.strictEqual(result.code, 'ALREADY_USED');
    });
    (0, node_test_1.it)('5. Token sai hoặc không tồn tại -> INVALID_TOKEN', () => {
        const contactDoc = createMockContact();
        const result = (0, verificationEngine_1.validateVerificationToken)({
            tokenDoc: null,
            contactDoc,
            now: baseDate,
        });
        assert.strictEqual(result.isValid, false);
        assert.strictEqual(result.code, 'INVALID_TOKEN');
    });
    (0, node_test_1.it)('6. Token không khớp contactId hoặc uid -> MISMATCH', () => {
        const tokenDoc = createMockToken({ contactId: 'contact_khac_999' });
        const contactDoc = createMockContact({ id: 'contact_abc123' });
        const result = (0, verificationEngine_1.validateVerificationToken)({
            tokenDoc,
            contactDoc,
            now: baseDate,
        });
        assert.strictEqual(result.isValid, false);
        assert.strictEqual(result.code, 'MISMATCH');
    });
    (0, node_test_1.it)('7. Liên hệ đích đã bị xóa khỏi hệ thống -> CONTACT_DELETED', () => {
        const tokenDoc = createMockToken();
        const result = (0, verificationEngine_1.validateVerificationToken)({
            tokenDoc,
            contactDoc: null, // Liên hệ không tồn tại
            now: baseDate,
        });
        assert.strictEqual(result.isValid, false);
        assert.strictEqual(result.code, 'CONTACT_DELETED');
    });
    (0, node_test_1.it)('8. Liên hệ đang bị tạm tắt (isActive = false) -> CONTACT_INACTIVE', () => {
        const tokenDoc = createMockToken();
        const contactDoc = createMockContact({ isActive: false });
        const result = (0, verificationEngine_1.validateVerificationToken)({
            tokenDoc,
            contactDoc,
            now: baseDate,
        });
        assert.strictEqual(result.isValid, false);
        assert.strictEqual(result.code, 'CONTACT_INACTIVE');
    });
    (0, node_test_1.it)('9. Token bị khóa do vượt quá số lần thử (Chống Brute-force) -> RATE_LIMITED_BRUTE_FORCE', () => {
        const tokenDoc = createMockToken({
            attempts: verificationEngine_1.MAX_TOKEN_ATTEMPTS,
        });
        const contactDoc = createMockContact();
        const result = (0, verificationEngine_1.validateVerificationToken)({
            tokenDoc,
            contactDoc,
            now: baseDate,
        });
        assert.strictEqual(result.isValid, false);
        assert.strictEqual(result.code, 'RATE_LIMITED_BRUTE_FORCE');
    });
    (0, node_test_1.it)('10. Token đã bị thu hồi khi người dùng yêu cầu mã mới -> REVOKED', () => {
        const tokenDoc = createMockToken({
            status: 'revoked',
        });
        const contactDoc = createMockContact();
        const result = (0, verificationEngine_1.validateVerificationToken)({
            tokenDoc,
            contactDoc,
            now: baseDate,
        });
        assert.strictEqual(result.isValid, false);
        assert.strictEqual(result.code, 'REVOKED');
    });
    (0, node_test_1.it)('11. Đánh giá hành động Consent: accept, decline, revoke', () => {
        const accept = (0, verificationEngine_1.evaluateConsentAction)('accept');
        assert.strictEqual(accept.valid, true);
        assert.strictEqual(accept.targetConsentStatus, 'accepted');
        const decline = (0, verificationEngine_1.evaluateConsentAction)('decline');
        assert.strictEqual(decline.valid, true);
        assert.strictEqual(decline.targetConsentStatus, 'declined');
        const revoke = (0, verificationEngine_1.evaluateConsentAction)('revoke');
        assert.strictEqual(revoke.valid, true);
        assert.strictEqual(revoke.targetConsentStatus, 'revoked');
        const invalid = (0, verificationEngine_1.evaluateConsentAction)('unknown_action');
        assert.strictEqual(invalid.valid, false);
    });
    (0, node_test_1.it)('12. Rate limiting cooldown (120 giây giữa các lần yêu cầu token)', () => {
        const lastRequest = new Date('2026-10-26T10:00:00.000Z');
        // 30 giây sau: phải bị chặn
        const check1 = (0, verificationEngine_1.isRateLimited)({
            lastRequestedAt: lastRequest,
            cooldownSeconds: verificationEngine_1.RATE_LIMIT_COOLDOWN_SECONDS,
            now: new Date('2026-10-26T10:00:30.000Z'),
        });
        assert.strictEqual(check1.isLimited, true);
        assert.strictEqual(check1.remainingSeconds, 90);
        // 121 giây sau: hợp lệ
        const check2 = (0, verificationEngine_1.isRateLimited)({
            lastRequestedAt: lastRequest,
            cooldownSeconds: verificationEngine_1.RATE_LIMIT_COOLDOWN_SECONDS,
            now: new Date('2026-10-26T10:02:01.000Z'),
        });
        assert.strictEqual(check2.isLimited, false);
        assert.strictEqual(check2.remainingSeconds, 0);
    });
    (0, node_test_1.it)('13. Che dấu email (maskEmail) bảo vệ thông tin cá nhân', () => {
        assert.strictEqual((0, verificationEngine_1.maskEmail)('nguyenvana@gmail.com'), 'ng***a@gmail.com');
        assert.strictEqual((0, verificationEngine_1.maskEmail)('ab@test.com'), 'a*@test.com');
        assert.strictEqual((0, verificationEngine_1.maskEmail)('contact@domain.vn'), 'co***t@domain.vn');
    });
    (0, node_test_1.it)('14. Nội dung giải thích minh bạch không khẳng định người dùng đã gặp nạn', () => {
        const explanation = (0, verificationEngine_1.getOptInExplanation)('Nguyễn Văn Chủ');
        assert.strictEqual(explanation.senderLabel, 'Nguyễn Văn Chủ');
        assert.ok(explanation.purpose.includes('chưa check-in đúng hạn'));
        assert.ok(explanation.disclaimer.includes('không khẳng định người dùng đã gặp nạn hay qua đời'));
    });
});
//# sourceMappingURL=contactVerification.test.js.map