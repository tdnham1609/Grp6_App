import { describe, it } from 'node:test';
import * as assert from 'node:assert';
import { Timestamp } from 'firebase-admin/firestore';
import {
  generateRawToken,
  hashToken,
  maskEmail,
  isRateLimited,
  validateVerificationToken,
  evaluateConsentAction,
  getOptInExplanation,
  TOKEN_LIFETIME_MS,
  MAX_TOKEN_ATTEMPTS,
  RATE_LIMIT_COOLDOWN_SECONDS,
} from '../src/verificationEngine';
import {
  VerificationTokenDoc,
  EmergencyContactDoc,
} from '../src/types';

describe('Contact Verification & Opt-in Consent Tests', () => {
  const baseDate = new Date('2026-10-26T10:00:00.000Z');

  function createMockContact(overrides?: Partial<EmergencyContactDoc>): EmergencyContactDoc {
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
      createdAt: Timestamp.fromDate(baseDate),
      updatedAt: Timestamp.fromDate(baseDate),
      ...overrides,
    };
  }

  function createMockToken(overrides?: Partial<VerificationTokenDoc>): VerificationTokenDoc {
    const rawToken = 'test_raw_token_32_bytes_super_secure';
    const expiresAt = new Date(baseDate.getTime() + TOKEN_LIFETIME_MS);

    return {
      tokenHash: hashToken(rawToken),
      uid: 'user_xyz789',
      contactId: 'contact_abc123',
      email: 'nguoithan@gmail.com',
      contactName: 'Nguyễn Văn Người Thân',
      userDisplayName: 'Chủ Tài Khoản',
      status: 'pending',
      attempts: 0,
      maxAttempts: MAX_TOKEN_ATTEMPTS,
      createdAt: Timestamp.fromDate(baseDate),
      expiresAt: Timestamp.fromDate(expiresAt),
      usedAt: null,
      lastAttemptAt: null,
      ...overrides,
    };
  }

  it('1. Tạo raw token ngẫu nhiên và mã băm SHA-256 an toàn', () => {
    const raw1 = generateRawToken();
    const raw2 = generateRawToken();
    assert.notStrictEqual(raw1, raw2);
    assert.strictEqual(raw1.length, 64); // 32 bytes hex = 64 characters

    const hash1 = hashToken(raw1);
    const hash2 = hashToken(raw1);
    assert.strictEqual(hash1, hash2, 'Hash của cùng token phải giống nhau');
    assert.notStrictEqual(hash1, raw1, 'Hash không được trùng với raw token');
  });

  it('2. Token hợp lệ -> VALID', () => {
    const tokenDoc = createMockToken();
    const contactDoc = createMockContact();

    const result = validateVerificationToken({
      tokenDoc,
      contactDoc,
      now: new Date('2026-10-26T12:00:00.000Z'), // 2 giờ sau khi tạo (vẫn trong hạn 24h)
    });

    assert.strictEqual(result.isValid, true);
    assert.strictEqual(result.code, 'VALID');
  });

  it('3. Token hết hạn (> 24 giờ) -> EXPIRED', () => {
    const tokenDoc = createMockToken();
    const contactDoc = createMockContact();

    // 25 giờ sau khi tạo
    const expiredTime = new Date(baseDate.getTime() + 25 * 60 * 60 * 1000);
    const result = validateVerificationToken({
      tokenDoc,
      contactDoc,
      now: expiredTime,
    });

    assert.strictEqual(result.isValid, false);
    assert.strictEqual(result.code, 'EXPIRED');
    assert.strictEqual(result.shouldMarkExpired, true);
  });

  it('4. Token đã sử dụng -> ALREADY_USED (Chống Replay Attack)', () => {
    const tokenDoc = createMockToken({
      status: 'used',
      usedAt: Timestamp.fromDate(new Date('2026-10-26T11:00:00.000Z')),
    });
    const contactDoc = createMockContact();

    const result = validateVerificationToken({
      tokenDoc,
      contactDoc,
      now: new Date('2026-10-26T12:00:00.000Z'),
    });

    assert.strictEqual(result.isValid, false);
    assert.strictEqual(result.code, 'ALREADY_USED');
  });

  it('5. Token sai hoặc không tồn tại -> INVALID_TOKEN', () => {
    const contactDoc = createMockContact();

    const result = validateVerificationToken({
      tokenDoc: null,
      contactDoc,
      now: baseDate,
    });

    assert.strictEqual(result.isValid, false);
    assert.strictEqual(result.code, 'INVALID_TOKEN');
  });

  it('6. Token không khớp contactId hoặc uid -> MISMATCH', () => {
    const tokenDoc = createMockToken({ contactId: 'contact_khac_999' });
    const contactDoc = createMockContact({ id: 'contact_abc123' });

    const result = validateVerificationToken({
      tokenDoc,
      contactDoc,
      now: baseDate,
    });

    assert.strictEqual(result.isValid, false);
    assert.strictEqual(result.code, 'MISMATCH');
  });

  it('7. Liên hệ đích đã bị xóa khỏi hệ thống -> CONTACT_DELETED', () => {
    const tokenDoc = createMockToken();

    const result = validateVerificationToken({
      tokenDoc,
      contactDoc: null, // Liên hệ không tồn tại
      now: baseDate,
    });

    assert.strictEqual(result.isValid, false);
    assert.strictEqual(result.code, 'CONTACT_DELETED');
  });

  it('8. Liên hệ đang bị tạm tắt (isActive = false) -> CONTACT_INACTIVE', () => {
    const tokenDoc = createMockToken();
    const contactDoc = createMockContact({ isActive: false });

    const result = validateVerificationToken({
      tokenDoc,
      contactDoc,
      now: baseDate,
    });

    assert.strictEqual(result.isValid, false);
    assert.strictEqual(result.code, 'CONTACT_INACTIVE');
  });

  it('9. Token bị khóa do vượt quá số lần thử (Chống Brute-force) -> RATE_LIMITED_BRUTE_FORCE', () => {
    const tokenDoc = createMockToken({
      attempts: MAX_TOKEN_ATTEMPTS,
    });
    const contactDoc = createMockContact();

    const result = validateVerificationToken({
      tokenDoc,
      contactDoc,
      now: baseDate,
    });

    assert.strictEqual(result.isValid, false);
    assert.strictEqual(result.code, 'RATE_LIMITED_BRUTE_FORCE');
  });

  it('10. Token đã bị thu hồi khi người dùng yêu cầu mã mới -> REVOKED', () => {
    const tokenDoc = createMockToken({
      status: 'revoked',
    });
    const contactDoc = createMockContact();

    const result = validateVerificationToken({
      tokenDoc,
      contactDoc,
      now: baseDate,
    });

    assert.strictEqual(result.isValid, false);
    assert.strictEqual(result.code, 'REVOKED');
  });

  it('11. Đánh giá hành động Consent: accept, decline, revoke', () => {
    const accept = evaluateConsentAction('accept');
    assert.strictEqual(accept.valid, true);
    assert.strictEqual(accept.targetConsentStatus, 'accepted');

    const decline = evaluateConsentAction('decline');
    assert.strictEqual(decline.valid, true);
    assert.strictEqual(decline.targetConsentStatus, 'declined');

    const revoke = evaluateConsentAction('revoke');
    assert.strictEqual(revoke.valid, true);
    assert.strictEqual(revoke.targetConsentStatus, 'revoked');

    const invalid = evaluateConsentAction('unknown_action');
    assert.strictEqual(invalid.valid, false);
  });

  it('12. Rate limiting cooldown (120 giây giữa các lần yêu cầu token)', () => {
    const lastRequest = new Date('2026-10-26T10:00:00.000Z');

    // 30 giây sau: phải bị chặn
    const check1 = isRateLimited({
      lastRequestedAt: lastRequest,
      cooldownSeconds: RATE_LIMIT_COOLDOWN_SECONDS,
      now: new Date('2026-10-26T10:00:30.000Z'),
    });
    assert.strictEqual(check1.isLimited, true);
    assert.strictEqual(check1.remainingSeconds, 90);

    // 121 giây sau: hợp lệ
    const check2 = isRateLimited({
      lastRequestedAt: lastRequest,
      cooldownSeconds: RATE_LIMIT_COOLDOWN_SECONDS,
      now: new Date('2026-10-26T10:02:01.000Z'),
    });
    assert.strictEqual(check2.isLimited, false);
    assert.strictEqual(check2.remainingSeconds, 0);
  });

  it('13. Che dấu email (maskEmail) bảo vệ thông tin cá nhân', () => {
    assert.strictEqual(maskEmail('nguyenvana@gmail.com'), 'ng***a@gmail.com');
    assert.strictEqual(maskEmail('ab@test.com'), 'a*@test.com');
    assert.strictEqual(maskEmail('contact@domain.vn'), 'co***t@domain.vn');
  });

  it('14. Nội dung giải thích minh bạch không khẳng định người dùng đã gặp nạn', () => {
    const explanation = getOptInExplanation('Nguyễn Văn Chủ');
    assert.strictEqual(explanation.senderLabel, 'Nguyễn Văn Chủ');
    assert.ok(explanation.purpose.includes('chưa check-in đúng hạn'));
    assert.ok(explanation.disclaimer.includes('không khẳng định người dùng đã gặp nạn hay qua đời'));
  });
});
