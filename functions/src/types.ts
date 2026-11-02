import { Timestamp } from 'firebase-admin/firestore';

/**
 * Trạng thái của sự kiện cảnh báo Dead Man's Switch
 */
export type AlertStatus =
  | 'overdue'             // Đã quá hạn check-in, đang trong thời gian gia hạn (grace period)
  | 'pending_alert'        // Hết thời gian gia hạn, chuẩn bị kích hoạt cảnh báo
  | 'dry_run_dispatched'  // Đã kích hoạt mô phỏng (Sandbox/Dry-run log, không gửi thật)
  | 'alert_sent'          // Cảnh báo thật đã gửi thành công tới tất cả liên hệ hợp lệ
  | 'partially_sent'      // Cảnh báo đã gửi thành công tới một phần liên hệ, có liên hệ lỗi
  | 'alert_failed'        // Gửi cảnh báo thất bại tới tất cả người nhận
  | 'cancelled';          // Người dùng đã check-in an toàn trở lại, cảnh báo được huỷ bỏ

/**
 * Chi tiết kết quả gửi cảnh báo cho từng người nhận (Idempotency & Isolation)
 */
export interface AlertRecipientRecord {
  contactId: string;
  email: string;
  name: string;
  status: 'pending' | 'sent' | 'failed' | 'skipped_dry_run';
  sentAt?: Timestamp | null;
  error?: string | null;
  attempts: number;
}

/**
 * Thông tin vị trí đính kèm cảnh báo (nếu người dùng bật chia sẻ)
 */
export interface AlertLocationData {
  latitude: number;
  longitude: number;
  address?: string | null;
  accuracy?: number | null;
  timestamp: Timestamp;
  isSharingEnabled: boolean;
}

/**
 * Cấu hình check-in của người dùng lưu tại users/{uid}/settings/checkin
 */
export interface CheckInSettings {
  intervalHours: number;
  reminderMinutesBefore: number;
  isReminderEnabled: boolean;
  isDeadManSwitchActive?: boolean; // Mặc định true nếu chưa set
  gracePeriodMinutes?: number;     // Mặc định 180 phút (3 giờ) nếu chưa set
  lastCheckInAt?: Timestamp | null;
  nextCheckInDueAt?: Timestamp | null;
  updatedAt: Timestamp;
  // Tuỳ chọn chia sẻ vị trí lên Cloud (nếu người dùng bật)
  isLocationSharingEnabled?: boolean;
  lastKnownLocation?: {
    latitude: number;
    longitude: number;
    accuracy?: number | null;
    timestamp: Timestamp;
  } | null;
}

/**
 * Bản ghi sự kiện cảnh báo lưu tại users/{uid}/alert_events/{eventId}
 */
export interface AlertEvent {
  id: string;
  uid: string;
  isDemo?: boolean;
  checkInDueAt: Timestamp;
  gracePeriodEndsAt: Timestamp;
  status: AlertStatus;
  detectedAt: Timestamp;
  resolvedAt?: Timestamp | null;
  cancellationReason?: string | null;
  recipients?: AlertRecipientRecord[] | null;
  location?: AlertLocationData | null;
  dryRunDetails?: {
    isDryRun: boolean;
    simulatedRecipientsCount: number;
    simulatedMessage: string;
    evaluatedAt: Timestamp;
  } | null;
}

/**
 * Kết quả phân tích trạng thái an toàn
 */
export interface SafetyEvaluation {
  action: 'NO_ACTION' | 'START_GRACE_PERIOD' | 'TRIGGER_DRY_RUN' | 'CANCEL_ALERT';
  reason: string;
  targetStatus?: AlertStatus;
  gracePeriodEndsAt?: Date;
}

/**
 * Trạng thái đồng ý nhận cảnh báo khẩn cấp
 */
export type ConsentStatus = 'pending' | 'accepted' | 'declined' | 'revoked';

/**
 * Trạng thái token xác minh
 */
export type TokenStatus = 'pending' | 'used' | 'expired' | 'revoked';

/**
 * Bản ghi token xác minh bảo mật lưu tại verification_tokens/{tokenHash}
 */
export interface VerificationTokenDoc {
  tokenHash: string; // SHA-256 hash của token (không bao giờ lưu raw token)
  uid: string;
  contactId: string;
  email: string;
  contactName: string;
  userDisplayName?: string | null;
  status: TokenStatus;
  attempts: number;
  maxAttempts: number;
  createdAt: Timestamp;
  expiresAt: Timestamp;
  usedAt?: Timestamp | null;
  lastAttemptAt?: Timestamp | null;
}

/**
 * Bản ghi EmergencyContact trong Firestore: users/{uid}/emergency_contacts/{contactId}
 */
export interface EmergencyContactDoc {
  id: string;
  uid: string;
  name: string;
  email: string;
  phoneNumber?: string | null;
  relationship: string;
  emailVerified: boolean;
  consentStatus: ConsentStatus;
  isActive: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  consentUpdatedAt?: Timestamp | null;
}
