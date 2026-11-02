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
exports.verifyContactPortal = exports.requestContactVerification = void 0;
const https_1 = require("firebase-functions/v2/https");
const https_2 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const verificationEngine_1 = require("./verificationEngine");
const emailService_1 = require("./emailService");
/**
 * 1. CALLABLE FUNCTION: requestContactVerification
 * Dành cho Flutter Client gọi khi thêm người liên hệ hoặc ấn nút "Gửi link xác minh"
 */
exports.requestContactVerification = (0, https_1.onCall)({
    cors: true,
    secrets: ['SEND_DEMO_ALERTS', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM'],
}, async (request) => {
    // 1. Kiểm tra xác thực người dùng
    if (!request.auth || !request.auth.uid) {
        throw new https_1.HttpsError('unauthenticated', 'Yêu cầu xác thực tài khoản để thực hiện thao tác này.');
    }
    const uid = request.auth.uid;
    const contactId = request.data?.contactId;
    if (!contactId || typeof contactId !== 'string') {
        throw new https_1.HttpsError('invalid-argument', 'Thiếu hoặc sai định dạng mã người liên hệ (contactId).');
    }
    const db = (0, firestore_1.getFirestore)();
    const now = new Date();
    const nowTimestamp = firestore_1.Timestamp.fromDate(now);
    // 2. Tìm liên hệ khẩn cấp trong CSDL
    const contactRef = db
        .collection('users')
        .doc(uid)
        .collection('emergency_contacts')
        .doc(contactId);
    const contactSnap = await contactRef.get();
    if (!contactSnap.exists) {
        throw new https_1.HttpsError('not-found', 'Không tìm thấy người liên hệ khẩn cấp trong tài khoản của bạn.');
    }
    const contact = contactSnap.data();
    // 3. Kiểm tra liên hệ có đang hoạt động không
    if (!contact.isActive) {
        throw new https_1.HttpsError('failed-precondition', 'Người liên hệ này đang bị tắt nhận cảnh báo. Hãy kích hoạt trước khi gửi xác minh.');
    }
    // 4. Kiểm tra Rate Limiting (chống spam yêu cầu liên tục)
    const tokensRef = db.collection('verification_tokens');
    const existingTokensSnap = await tokensRef
        .where('uid', '==', uid)
        .where('contactId', '==', contactId)
        .where('status', '==', 'pending')
        .orderBy('createdAt', 'desc')
        .limit(1)
        .get();
    if (!existingTokensSnap.empty) {
        const latestToken = existingTokensSnap.docs[0].data();
        const rateLimitCheck = (0, verificationEngine_1.isRateLimited)({
            lastRequestedAt: latestToken.createdAt.toDate(),
            cooldownSeconds: verificationEngine_1.RATE_LIMIT_COOLDOWN_SECONDS,
            now,
        });
        if (rateLimitCheck.isLimited) {
            throw new https_1.HttpsError('resource-exhausted', `Vui lòng chờ thêm ${rateLimitCheck.remainingSeconds} giây trước khi gửi lại link xác minh.`);
        }
    }
    // 5. Vô hiệu hóa (revoke) tất cả token cũ chưa dùng của contact này
    const allPendingSnap = await tokensRef
        .where('uid', '==', uid)
        .where('contactId', '==', contactId)
        .where('status', '==', 'pending')
        .get();
    const batch = db.batch();
    for (const doc of allPendingSnap.docs) {
        batch.update(doc.ref, {
            status: 'revoked',
            usedAt: nowTimestamp,
        });
    }
    // 6. Tạo token ngẫu nhiên bảo mật cao và tính mã băm SHA-256
    const rawToken = (0, verificationEngine_1.generateRawToken)();
    const tokenHash = (0, verificationEngine_1.hashToken)(rawToken);
    const expiresAt = new Date(now.getTime() + verificationEngine_1.TOKEN_LIFETIME_MS);
    // Lấy tên hiển thị của người dùng (từ Auth hoặc User Profile)
    const userDocSnap = await db.collection('users').doc(uid).get();
    const userProfile = userDocSnap.data();
    const userDisplayName = userProfile?.displayName ||
        request.auth.token.name ||
        request.auth.token.email ||
        'Người dùng Sinh Tử';
    const tokenDocData = {
        tokenHash,
        uid,
        contactId,
        email: contact.email,
        contactName: contact.name,
        userDisplayName,
        status: 'pending',
        attempts: 0,
        maxAttempts: verificationEngine_1.MAX_TOKEN_ATTEMPTS,
        createdAt: nowTimestamp,
        expiresAt: firestore_1.Timestamp.fromDate(expiresAt),
        usedAt: null,
        lastAttemptAt: null,
    };
    const targetTokenRef = tokensRef.doc(tokenHash);
    batch.set(targetTokenRef, tokenDocData);
    await batch.commit();
    // 7. Tạo link xác minh an toàn
    // URL dẫn đến HTTPS endpoint verifyContactPortal
    const projectId = process.env.GCLOUD_PROJECT || 'sinhtuapp';
    const region = 'us-central1';
    const portalBaseUrl = process.env.VERIFICATION_PORTAL_BASE_URL ||
        `https://${region}-${projectId}.cloudfunctions.net/verifyContactPortal`;
    const verificationUrl = `${portalBaseUrl.replace(/\/$/, '')}?token=${encodeURIComponent(rawToken)}`;
    const emailService = new emailService_1.EmailService();
    const delivery = await emailService.sendContactVerificationEmail({
        recipientEmail: contact.email,
        contactName: contact.name,
        userName: userDisplayName,
        verificationUrl,
        expiresAt,
    });
    const isDryRun = !delivery.success;
    const message = delivery.success
        ? `Đã gửi liên kết xác minh tới ${(0, verificationEngine_1.maskEmail)(contact.email)}.`
        : emailService.hasValidConfiguration(true)
            ? `Không gửi được email tới ${(0, verificationEngine_1.maskEmail)(contact.email)}. Vẫn có thể sao chép link để xác minh thủ công.`
            : 'Email xác minh đang ở chế độ Dry-Run. Hãy cấu hình SMTP và SEND_DEMO_ALERTS để gửi email thật.';
    // 8. LOG BẢO MẬT: TUYỆT ĐỐI KHÔNG GHI RAW TOKEN VÀO CLOUD LOGGING
    logger.info(`[Verification] Đã tạo mã xác minh mới cho contactId: ${contactId}, email: ${(0, verificationEngine_1.maskEmail)(contact.email)}, tokenHash: ${tokenHash.slice(0, 10)}... (Email sent: ${delivery.success}).`);
    return {
        success: true,
        message,
        emailMasked: (0, verificationEngine_1.maskEmail)(contact.email),
        expiresAt: expiresAt.toISOString(),
        isDryRun,
        // Trả link dự phòng cho bản demo nếu SMTP chưa được cấu hình hoặc gửi thất bại.
        verificationUrl,
    };
});
/**
 * 2. HTTPS ENDPOINT: verifyContactPortal
 * Cổng giao tiếp Web (Web Portal) cho người liên hệ xác minh email và chọn đồng ý/từ chối nhận cảnh báo
 */
exports.verifyContactPortal = (0, https_2.onRequest)({
    cors: true,
}, async (req, res) => {
    const db = (0, firestore_1.getFirestore)();
    const now = new Date();
    const nowTimestamp = firestore_1.Timestamp.fromDate(now);
    // Lấy raw token từ query param (GET) hoặc body (POST)
    const rawToken = req.query.token || req.body?.token;
    const action = req.body?.action;
    if (!rawToken || typeof rawToken !== 'string') {
        res.status(400).send(renderHtmlPage({
            title: 'Mã xác minh không hợp lệ',
            statusType: 'error',
            heading: 'Liên kết không hợp lệ',
            message: 'Mã xác minh không được cung cấp hoặc sai định dạng. Vui lòng kiểm tra lại liên kết trong email.',
        }));
        return;
    }
    const tokenHash = (0, verificationEngine_1.hashToken)(rawToken);
    const tokenRef = db.collection('verification_tokens').doc(tokenHash);
    const tokenSnap = await tokenRef.get();
    if (!tokenSnap.exists) {
        res.status(404).send(renderHtmlPage({
            title: 'Không tìm thấy liên kết',
            statusType: 'error',
            heading: 'Mã xác minh không tồn tại',
            message: 'Liên kết này không tồn tại hoặc đã bị xóa khỏi hệ thống.',
        }));
        return;
    }
    const tokenDoc = tokenSnap.data();
    // Tăng số lần truy cập attempts để chống brute-force
    await tokenRef.update({
        attempts: (tokenDoc.attempts || 0) + 1,
        lastAttemptAt: nowTimestamp,
    });
    // Lấy thông tin liên hệ từ CSDL
    const contactRef = db
        .collection('users')
        .doc(tokenDoc.uid)
        .collection('emergency_contacts')
        .doc(tokenDoc.contactId);
    const contactSnap = await contactRef.get();
    const contactDoc = contactSnap.exists
        ? contactSnap.data()
        : null;
    // Thẩm định bằng Verification Engine
    const validation = (0, verificationEngine_1.validateVerificationToken)({
        tokenDoc,
        contactDoc,
        now,
    });
    if (validation.shouldMarkExpired) {
        await tokenRef.update({ status: 'expired' });
    }
    if (!validation.isValid) {
        res.status(400).send(renderHtmlPage({
            title: 'Xác minh thất bại',
            statusType: 'error',
            heading: 'Không thể xử lý yêu cầu',
            message: validation.errorMessage || 'Mã xác minh không hợp lệ.',
        }));
        return;
    }
    const currentContact = contactDoc;
    // Tự động đánh dấu xác minh email (emailVerified = true) nếu chưa được đánh dấu
    if (!currentContact.emailVerified) {
        await contactRef.update({
            emailVerified: true,
            updatedAt: nowTimestamp,
        });
        logger.info(`[Verification] Đã xác minh địa chỉ email thành công cho contactId: ${currentContact.id}.`);
    }
    // NẾU LÀ YÊU CẦU POST: Xử lý hành động Đồng ý (accept) / Từ chối (decline) / Thu hồi (revoke)
    if (req.method === 'POST' && action) {
        const evaluation = (0, verificationEngine_1.evaluateConsentAction)(action);
        if (!evaluation.valid || !evaluation.targetConsentStatus) {
            res.status(400).send(renderHtmlPage({
                title: 'Hành động không hợp lệ',
                statusType: 'error',
                heading: 'Thao tác không hợp lệ',
                message: evaluation.userFacingMessage || 'Hành động không được hỗ trợ.',
            }));
            return;
        }
        // Cập nhật trạng thái consent trong CSDL
        await contactRef.update({
            consentStatus: evaluation.targetConsentStatus,
            consentUpdatedAt: nowTimestamp,
            updatedAt: nowTimestamp,
        });
        // Nếu từ chối hoặc thu hồi, đánh dấu token là đã dùng
        if (action === 'decline' || action === 'revoke') {
            await tokenRef.update({
                status: 'used',
                usedAt: nowTimestamp,
            });
        }
        logger.info(`[Verification] Người liên hệ ${currentContact.id} đã cập nhật sự đồng ý: ${evaluation.targetConsentStatus}.`);
        res.status(200).send(renderHtmlPage({
            title: 'Cập nhật thành công',
            statusType: 'success',
            heading: 'Ghi nhận phản hồi thành công',
            message: evaluation.userFacingMessage,
            userDisplayName: tokenDoc.userDisplayName,
            consentStatus: evaluation.targetConsentStatus,
            rawToken,
        }));
        return;
    }
    // NẾU LÀ YÊU CẦU GET: Render giao diện Opt-in Portal để người nhận đưa ra quyết định
    const explanation = (0, verificationEngine_1.getOptInExplanation)(tokenDoc.userDisplayName);
    res.status(200).send(renderOptInPortalHtml({
        rawToken,
        contactName: currentContact.name,
        contactEmail: (0, verificationEngine_1.maskEmail)(currentContact.email),
        userDisplayName: explanation.senderLabel,
        purposeText: explanation.purpose,
        disclaimerText: explanation.disclaimer,
        currentConsent: currentContact.consentStatus,
    }));
});
/**
 * Hàm dựng giao diện HTML Portal Opt-In Material 3 (Deep Ocean & Emerald Cyan)
 */
function renderOptInPortalHtml(params) {
    const { rawToken, contactName, contactEmail, userDisplayName, purposeText, disclaimerText, currentConsent, } = params;
    return `<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Xác minh Liên hệ Khẩn cấp — Sinh Tử</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg-dark: #082F49;
      --bg-body: #F4F7F9;
      --teal-primary: #078D83;
      --teal-hover: #06726A;
      --text-dark: #0F172A;
      --text-muted: #64748B;
      --card-bg: #FFFFFF;
      --danger: #EF4444;
      --danger-hover: #DC2626;
      --border: #E2E8F0;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Plus Jakarta Sans', sans-serif;
      background-color: var(--bg-body);
      color: var(--text-dark);
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      padding: 20px;
    }
    .container {
      background: var(--card-bg);
      max-width: 580px;
      width: 100%;
      border-radius: 24px;
      box-shadow: 0 20px 40px -15px rgba(8, 47, 73, 0.12);
      overflow: hidden;
      border: 1px solid var(--border);
    }
    .header {
      background: linear-gradient(135deg, #082F49 0%, #0D3E5E 100%);
      color: #FFFFFF;
      padding: 32px 28px;
      text-align: center;
    }
    .badge {
      display: inline-block;
      background: rgba(7, 141, 131, 0.25);
      color: #14B8A6;
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 1px;
      text-transform: uppercase;
      padding: 6px 14px;
      border-radius: 100px;
      margin-bottom: 12px;
      border: 1px solid rgba(20, 184, 166, 0.4);
    }
    .header h1 {
      font-size: 24px;
      font-weight: 700;
      margin-bottom: 6px;
    }
    .header p {
      font-size: 14px;
      color: #94A3B8;
    }
    .body {
      padding: 32px 28px;
    }
    .verified-banner {
      background: #F0FDF4;
      border: 1px solid #BBF7D0;
      color: #166534;
      padding: 12px 16px;
      border-radius: 14px;
      display: flex;
      align-items: center;
      gap: 10px;
      font-size: 13.5px;
      font-weight: 600;
      margin-bottom: 24px;
    }
    .card-info {
      background: #F8FAFC;
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 20px;
      margin-bottom: 20px;
      line-height: 1.6;
    }
    .card-info h2 {
      font-size: 16px;
      font-weight: 700;
      color: var(--bg-dark);
      margin-bottom: 8px;
    }
    .card-info p {
      font-size: 14px;
      color: #334155;
    }
    .disclaimer {
      font-size: 12.5px;
      color: var(--text-muted);
      line-height: 1.5;
      background: #FFFBEB;
      border-left: 4px solid #F59E0B;
      padding: 12px 16px;
      border-radius: 8px;
      margin-bottom: 28px;
    }
    .btn-group {
      display: flex;
      flex-direction: column;
      gap: 12px;
    }
    .btn {
      display: inline-flex;
      justify-content: center;
      align-items: center;
      padding: 15px 24px;
      font-size: 15px;
      font-weight: 600;
      border-radius: 14px;
      cursor: pointer;
      border: none;
      transition: all 0.2s ease;
      width: 100%;
    }
    .btn-primary {
      background: var(--teal-primary);
      color: #FFFFFF;
    }
    .btn-primary:hover {
      background: var(--teal-hover);
    }
    .btn-outline {
      background: #FFFFFF;
      color: var(--text-muted);
      border: 1px solid var(--border);
    }
    .btn-outline:hover {
      background: #F1F5F9;
      color: var(--text-dark);
    }
    .btn-danger-outline {
      background: #FFFFFF;
      color: var(--danger);
      border: 1px solid #FECACA;
    }
    .btn-danger-outline:hover {
      background: #FEF2F2;
    }
    .footer {
      text-align: center;
      font-size: 12px;
      color: var(--text-muted);
      margin-top: 24px;
      padding-top: 20px;
      border-top: 1px solid var(--border);
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="badge">Dead Man’s Switch</div>
      <h1>Xác nhận Người liên hệ Khẩn cấp</h1>
      <p>Ứng dụng Sinh Tử — Thiết lập an toàn cho ${userDisplayName}</p>
    </div>
    <div class="body">
      <div class="verified-banner">
        <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor">
          <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
        </svg>
        <span>Địa chỉ email <strong>${contactEmail}</strong> đã được xác minh.</span>
      </div>

      <div class="card-info">
        <h2>Xin chào ${contactName},</h2>
        <p>${purposeText}</p>
      </div>

      <div class="disclaimer">
        ${disclaimerText}
      </div>

      <form method="POST" action="">
        <input type="hidden" name="token" value="${rawToken}">
        <div class="btn-group">
          ${currentConsent === 'accepted' ? `
            <div style="text-align: center; padding: 12px; background: #E6FFFA; border-radius: 12px; color: #047481; font-weight: 600; margin-bottom: 8px;">
              ✓ Bạn hiện ĐÃ ĐỒNG Ý nhận thông báo từ người dùng này.
            </div>
            <button type="submit" name="action" value="revoke" class="btn btn-danger-outline">
              Thu hồi sự đồng ý (Ngừng nhận cảnh báo)
            </button>
          ` : `
            <button type="submit" name="action" value="accept" class="btn btn-primary">
              Đồng ý nhận cảnh báo khẩn cấp
            </button>
            <button type="submit" name="action" value="decline" class="btn btn-outline">
              Từ chối nhận cảnh báo
            </button>
          `}
        </div>
      </form>

      <div class="footer">
        Hệ thống Sinh Tử tôn trọng quyền riêng tư của bạn. Bạn có thể thay đổi hoặc thu hồi quyết định bất kỳ lúc nào qua liên kết này.
      </div>
    </div>
  </div>
</body>
</html>`;
}
/**
 * Hàm render trang thông báo kết quả chung
 */
function renderHtmlPage(params) {
    const { title, statusType, heading, message, consentStatus, rawToken } = params;
    const isSuccess = statusType === 'success';
    return `<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title} — Sinh Tử</title>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    body {
      font-family: 'Plus Jakarta Sans', sans-serif;
      background-color: #F4F7F9;
      color: #0F172A;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      padding: 20px;
      margin: 0;
    }
    .card {
      background: #FFFFFF;
      max-width: 500px;
      width: 100%;
      border-radius: 24px;
      padding: 36px 28px;
      text-align: center;
      box-shadow: 0 20px 40px -15px rgba(8, 47, 73, 0.12);
      border: 1px solid #E2E8F0;
    }
    .icon {
      width: 64px;
      height: 64px;
      border-radius: 50%;
      display: inline-flex;
      justify-content: center;
      align-items: center;
      margin-bottom: 20px;
      background: ${isSuccess ? '#ECFDF5' : '#FEF2F2'};
      color: ${isSuccess ? '#10B981' : '#EF4444'};
    }
    h1 { font-size: 22px; font-weight: 700; color: #082F49; margin-bottom: 12px; }
    p { font-size: 14.5px; color: #64748B; line-height: 1.6; margin-bottom: 24px; }
    .status-badge {
      display: inline-block;
      padding: 8px 16px;
      border-radius: 100px;
      font-size: 13px;
      font-weight: 600;
      margin-bottom: 20px;
      background: ${consentStatus === 'accepted' ? '#E6FFFA' : '#F1F5F9'};
      color: ${consentStatus === 'accepted' ? '#047481' : '#475569'};
    }
    .btn {
      display: inline-block;
      padding: 12px 24px;
      background: #082F49;
      color: #FFFFFF;
      text-decoration: none;
      border-radius: 12px;
      font-size: 14px;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">
      ${isSuccess
        ? `<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 6L9 17l-5-5"/></svg>`
        : `<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M15 9l-6 6M9 9l6 6"/></svg>`}
    </div>
    <h1>${heading}</h1>
    <p>${message}</p>
    ${consentStatus ? `<div class="status-badge">Trạng thái: <strong>${consentStatus}</strong></div><br>` : ''}
    ${rawToken ? `<a href="?token=${rawToken}" class="btn">Quay lại trang xác nhận</a>` : ''}
  </div>
</body>
</html>`;
}
//# sourceMappingURL=contactVerification.js.map