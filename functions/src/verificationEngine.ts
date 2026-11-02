import * as crypto from 'crypto';
import {
  VerificationTokenDoc,
  EmergencyContactDoc,
  ConsentStatus,
} from './types';

/**
 * Thời hạn hiệu lực của token xác minh (24 giờ tính bằng mili-giây)
 */
export const TOKEN_LIFETIME_MS = 24 * 60 * 60 * 1000;

/**
 * Giới hạn số lần thử nhập/truy cập sai token trước khi khóa token (chống brute-force)
 */
export const MAX_TOKEN_ATTEMPTS = 5;

/**
 * Thời gian chờ tối thiểu giữa 2 lần yêu cầu tạo token mới cho 1 liên hệ (120 giây)
 */
export const RATE_LIMIT_COOLDOWN_SECONDS = 120;

/**
 * Tạo token ngẫu nhiên bảo mật cao (256-bit entropy)
 * Token gốc này CHỈ được gửi trong link xác minh, KHÔNG BAO GIỜ lưu vào CSDL
 */
export function generateRawToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

/**
 * Băm token bằng thuật toán SHA-256 an toàn
 * Chỉ chuỗi hash này mới được lưu trữ trong Firestore (verification_tokens/{tokenHash})
 */
export function hashToken(rawToken: string): string {
  return crypto.createHash('sha256').update(rawToken).digest('hex');
}

/**
 * Che giấu một phần email để bảo vệ quyền riêng tư
 * Ví dụ: nguyenvana@gmail.com -> ng***a@gmail.com
 */
export function maskEmail(email: string): string {
  const parts = email.split('@');
  if (parts.length !== 2) return '***';
  const name = parts[0];
  const domain = parts[1];

  if (name.length <= 2) {
    return `${name[0]}*@${domain}`;
  }
  const start = name.slice(0, 2);
  const end = name.slice(-1);
  return `${start}***${end}@${domain}`;
}

/**
 * Kiểm tra xem yêu cầu có vi phạm tần suất (Rate limit cooldown) hay không
 */
export function isRateLimited(params: {
  lastRequestedAt: Date | null | undefined;
  cooldownSeconds?: number;
  now: Date;
}): { isLimited: boolean; remainingSeconds: number } {
  const { lastRequestedAt, cooldownSeconds = RATE_LIMIT_COOLDOWN_SECONDS, now } = params;
  if (!lastRequestedAt) {
    return { isLimited: false, remainingSeconds: 0 };
  }

  const elapsedSeconds = Math.floor((now.getTime() - lastRequestedAt.getTime()) / 1000);
  if (elapsedSeconds < cooldownSeconds) {
    return {
      isLimited: true,
      remainingSeconds: cooldownSeconds - elapsedSeconds,
    };
  }

  return { isLimited: false, remainingSeconds: 0 };
}

/**
 * Kết quả thẩm định token xác minh
 */
export type TokenValidationCode =
  | 'VALID'
  | 'INVALID_TOKEN'
  | 'RATE_LIMITED_BRUTE_FORCE'
  | 'ALREADY_USED'
  | 'EXPIRED'
  | 'REVOKED'
  | 'CONTACT_DELETED'
  | 'CONTACT_INACTIVE'
  | 'MISMATCH';

export interface TokenValidationResult {
  isValid: boolean;
  code: TokenValidationCode;
  errorMessage?: string;
  shouldMarkExpired?: boolean;
}

/**
 * Động cơ thẩm định tính hợp lệ của Token xác minh (Pure Function)
 */
export function validateVerificationToken(params: {
  tokenDoc: VerificationTokenDoc | null | undefined;
  contactDoc: EmergencyContactDoc | null | undefined;
  now: Date;
}): TokenValidationResult {
  const { tokenDoc, contactDoc, now } = params;

  // 1. Token không tồn tại trong hệ thống
  if (!tokenDoc) {
    return {
      isValid: false,
      code: 'INVALID_TOKEN',
      errorMessage: 'Liên kết xác minh không hợp lệ hoặc không tồn tại.',
    };
  }

  // 2. Chống brute-force: vượt quá số lần thử tối đa
  if (tokenDoc.attempts >= (tokenDoc.maxAttempts || MAX_TOKEN_ATTEMPTS)) {
    return {
      isValid: false,
      code: 'RATE_LIMITED_BRUTE_FORCE',
      errorMessage: 'Mã xác minh đã bị khóa do thử quá số lần quy định.',
    };
  }

  // 3. Token đã qua sử dụng (Chống replay attack)
  if (tokenDoc.status === 'used') {
    return {
      isValid: false,
      code: 'ALREADY_USED',
      errorMessage: 'Liên kết xác minh này đã được sử dụng trước đó.',
    };
  }

  // 4. Token đã bị hủy (ví dụ: khi người dùng yêu cầu gửi mã mới)
  if (tokenDoc.status === 'revoked') {
    return {
      isValid: false,
      code: 'REVOKED',
      errorMessage: 'Liên kết xác minh này đã được thay thế bằng một liên kết mới hơn.',
    };
  }

  // 5. Kiểm tra thời hạn token
  const expiresAtDate = tokenDoc.expiresAt.toDate();
  if (now > expiresAtDate || tokenDoc.status === 'expired') {
    return {
      isValid: false,
      code: 'EXPIRED',
      shouldMarkExpired: tokenDoc.status !== 'expired',
      errorMessage: 'Liên kết xác minh đã hết hạn sử dụng (hạn 24 giờ). Vui lòng yêu cầu người gửi cấp liên kết mới.',
    };
  }

  // 6. Kiểm tra liên hệ đích trong CSDL
  if (!contactDoc) {
    return {
      isValid: false,
      code: 'CONTACT_DELETED',
      errorMessage: 'Người liên hệ này không còn tồn tại trên hệ thống.',
    };
  }

  // 7. Liên hệ đang bị người dùng tắt (isActive = false)
  if (!contactDoc.isActive) {
    return {
      isValid: false,
      code: 'CONTACT_INACTIVE',
      errorMessage: 'Người liên hệ này hiện đang tạm ngưng nhận cảnh báo.',
    };
  }

  // 8. Kiểm tra khớp UID và ContactId
  if (contactDoc.id !== tokenDoc.contactId || contactDoc.uid !== tokenDoc.uid) {
    return {
      isValid: false,
      code: 'MISMATCH',
      errorMessage: 'Thông tin liên kết xác minh không trùng khớp với người liên hệ.',
    };
  }

  return {
    isValid: true,
    code: 'VALID',
  };
}

/**
 * Xử lý hành động đồng ý / từ chối / thu hồi của người liên hệ
 */
export function evaluateConsentAction(action: string): {
  valid: boolean;
  targetConsentStatus?: ConsentStatus;
  userFacingMessage?: string;
} {
  switch (action) {
    case 'accept':
      return {
        valid: true,
        targetConsentStatus: 'accepted',
        userFacingMessage: 'Bạn đã đồng ý nhận cảnh báo khẩn cấp khi người dùng chưa check-in đúng hạn.',
      };
    case 'decline':
      return {
        valid: true,
        targetConsentStatus: 'declined',
        userFacingMessage: 'Bạn đã từ chối nhận cảnh báo từ tài khoản này. Hệ thống sẽ không gửi cảnh báo cho bạn.',
      };
    case 'revoke':
      return {
        valid: true,
        targetConsentStatus: 'revoked',
        userFacingMessage: 'Bạn đã thu hồi sự đồng ý nhận cảnh báo. Bạn có thể thay đổi lại quyết định bất kỳ lúc nào.',
      };
    default:
      return {
        valid: false,
        userFacingMessage: 'Hành động phản hồi không hợp lệ.',
      };
  }
}

/**
 * Tạo nội dung thông điệp giải thích minh bạch cho người nhận
 */
export function getOptInExplanation(displayName?: string | null): {
  senderLabel: string;
  purpose: string;
  disclaimer: string;
} {
  const name = displayName && displayName.trim().length > 0 ? displayName.trim() : 'Người dùng Sinh Tử';
  return {
    senderLabel: name,
    purpose:
      `Bạn được chỉ định làm người liên hệ khẩn cấp cho ${name}. Hệ thống Sinh Tử (Dead Man’s Switch) hoạt động theo cơ chế an toàn cá nhân: nếu người dùng không thực hiện check-in định kỳ và hết thời gian gia hạn an toàn, hệ thống sẽ gửi thông báo để bạn biết họ chưa check-in đúng hạn.`,
    disclaimer:
      'Lưu ý: Thông báo quá hạn check-in không khẳng định người dùng đã gặp nạn hay qua đời, mà chỉ thể hiện hệ thống chưa nhận được tín hiệu xác nhận an toàn từ thiết bị của họ. Bạn có toàn quyền chấp thuận, từ chối hoặc thu hồi sự đồng ý nhận thông báo bất kỳ lúc nào.',
  };
}
