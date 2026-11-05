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
exports.syncTrustedStatus = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const firestore_2 = require("firebase-admin/firestore");
const logger = __importStar(require("firebase-functions/logger"));
exports.syncTrustedStatus = (0, firestore_1.onDocumentWritten)("users/{uid}/emergency_contacts/{contactId}", async (event) => {
    const uid = event.params.uid;
    const db = (0, firestore_2.getFirestore)();
    try {
        const contacts = await db
            .collection("users")
            .doc(uid)
            .collection("emergency_contacts")
            .get();
        const trustedEmails = new Set();
        contacts.forEach((snapshot) => {
            const contact = snapshot.data();
            const email = typeof contact.email === "string"
                ? contact.email.trim().toLowerCase()
                : "";
            if (email &&
                contact.isActive !== false &&
                contact.emailVerified === true &&
                contact.consentStatus === "accepted") {
                trustedEmails.add(email);
            }
        });
        const [profileSnapshot, settingsSnapshot] = await Promise.all([
            db.collection("users").doc(uid).get(),
            db.collection("users").doc(uid).collection("settings").doc("checkin").get(),
        ]);
        const profile = profileSnapshot.data();
        const settings = settingsSnapshot.data();
        await db.collection("trustedStatuses").doc(uid).set({
            ownerUid: uid,
            ownerName: typeof profile?.displayName === "string" &&
                profile.displayName.trim()
                ? profile.displayName.trim()
                : typeof profile?.email === "string" &&
                    profile.email.trim()
                    ? profile.email.trim()
                    : "Người cần theo dõi",
            relationship: "Người thân khẩn cấp",
            trustedEmails: [...trustedEmails],
            relationshipsUpdatedAt: firestore_2.FieldValue.serverTimestamp(),
            isDeadManSwitchActive: settings?.isDeadManSwitchActive !== false,
            lastCheckInAt: settings?.lastCheckInAt instanceof firestore_2.Timestamp
                ? settings.lastCheckInAt
                : null,
            nextCheckInDueAt: settings?.nextCheckInDueAt instanceof firestore_2.Timestamp
                ? settings.nextCheckInDueAt
                : null,
            updatedAt: firestore_2.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    catch (error) {
        logger.error("Không thể đồng bộ trustedStatuses", {
            uid,
            error,
        });
        throw error;
    }
});
//# sourceMappingURL=trustedStatusSync.js.map