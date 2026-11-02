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
exports.sendDemoAlert = void 0;
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const emailService_1 = require("./emailService");
const reverseGeocoding_1 = require("./reverseGeocoding");
const DEMO_ALERT_COOLDOWN_MS = 60 * 1000;
/** Send a clearly labeled real email to contacts who verified and accepted alerts. */
exports.sendDemoAlert = (0, https_1.onCall)({
    secrets: ['SEND_DEMO_ALERTS', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM'],
}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Vui lòng đăng nhập để gửi email demo.');
    }
    const emailService = new emailService_1.EmailService();
    if (!emailService.hasValidConfiguration(true)) {
        throw new https_1.HttpsError('failed-precondition', 'Email demo chưa được cấu hình. Hãy thiết lập SMTP và bật SEND_DEMO_ALERTS trên Firebase.');
    }
    const db = (0, firestore_1.getFirestore)();
    const userRef = db.collection('users').doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
        throw new https_1.HttpsError('failed-precondition', 'Không tìm thấy hồ sơ người dùng.');
    }
    const contactsSnap = await userRef
        .collection('emergency_contacts')
        .where('isActive', '==', true)
        .get();
    const eligibleContacts = contactsSnap.docs
        .map((doc) => doc.data())
        .filter((contact) => contact.emailVerified === true && contact.consentStatus === 'accepted');
    if (eligibleContacts.length === 0) {
        throw new https_1.HttpsError('failed-precondition', 'Chưa có liên hệ đang hoạt động đã xác minh email và đồng ý nhận cảnh báo.');
    }
    const now = firestore_1.Timestamp.now();
    const cooldownRef = db.collection('demo_alert_rate_limits').doc(uid);
    await db.runTransaction(async (transaction) => {
        const cooldownSnap = await transaction.get(cooldownRef);
        const lastSentAt = cooldownSnap.get('lastSentAt');
        if (lastSentAt && now.toMillis() - lastSentAt.toMillis() < DEMO_ALERT_COOLDOWN_MS) {
            throw new https_1.HttpsError('resource-exhausted', 'Vui lòng chờ một phút trước khi gửi email demo tiếp theo.');
        }
        transaction.set(cooldownRef, { lastSentAt: now });
    });
    const eventId = `demo_${now.toMillis()}`;
    const eventRef = userRef.collection('alert_events').doc(eventId);
    const pendingRecipients = eligibleContacts.map((contact) => ({
        contactId: contact.id,
        email: contact.email,
        name: contact.name,
        status: 'pending',
        sentAt: null,
        error: null,
        attempts: 0,
    }));
    const event = {
        id: eventId,
        uid,
        isDemo: true,
        checkInDueAt: now,
        gracePeriodEndsAt: now,
        status: 'pending_alert',
        detectedAt: now,
        resolvedAt: null,
        cancellationReason: null,
        recipients: pendingRecipients,
    };
    await eventRef.set(event);
    const userName = userSnap.data()?.displayName || 'Người dùng Sinh Tử';
    const settingsSnap = await userRef.collection('settings').doc('checkin').get();
    const settings = settingsSnap.data();
    const savedLocation = settings?.lastKnownLocation;
    let location = null;
    if (settings?.isLocationSharingEnabled === true &&
        savedLocation &&
        Number.isFinite(savedLocation.latitude) &&
        Number.isFinite(savedLocation.longitude)) {
        location = {
            latitude: savedLocation.latitude,
            longitude: savedLocation.longitude,
            accuracy: savedLocation.accuracy,
            timestamp: savedLocation.timestamp,
            isSharingEnabled: true,
            address: await (0, reverseGeocoding_1.reverseGeocodeAddress)(savedLocation.latitude, savedLocation.longitude),
        };
    }
    const recipientResults = [];
    for (const contact of eligibleContacts) {
        const result = await emailService.sendAlertEmail({
            recipient: {
                contactId: contact.id,
                email: contact.email,
                name: contact.name,
            },
            userName,
            dueDate: now.toDate(),
            gracePeriodEndsAt: now.toDate(),
            location,
            isDemo: true,
        });
        if (result.status === 'sent')
            result.sentAt = firestore_1.Timestamp.now();
        recipientResults.push(result);
        await eventRef.set({ recipients: recipientResults }, { merge: true });
    }
    const sentCount = recipientResults.filter((recipient) => recipient.status === 'sent').length;
    const failedCount = recipientResults.length - sentCount;
    const status = sentCount === recipientResults.length
        ? 'alert_sent'
        : sentCount > 0
            ? 'partially_sent'
            : 'alert_failed';
    await eventRef.set({ status, resolvedAt: firestore_1.Timestamp.now(), recipients: recipientResults }, { merge: true });
    logger.info(`[DemoAlert] Demo event ${eventId} completed for ${uid}: ${sentCount}/${recipientResults.length} sent.`);
    return {
        eventId,
        sentCount,
        failedCount,
        totalCount: recipientResults.length,
        recipients: recipientResults.map(({ name, email, status: recipientStatus }) => ({
            name,
            email,
            status: recipientStatus,
        })),
    };
});
//# sourceMappingURL=demoAlert.js.map