import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

type ContactData = {
  email?: unknown;
  emailVerified?: unknown;
  consentStatus?: unknown;
  isActive?: unknown;
};

export const syncTrustedStatus = onDocumentWritten(
  "users/{uid}/emergency_contacts/{contactId}",
  async (event) => {
    const uid = event.params.uid;
    const db = getFirestore();

    try {
      const contacts = await db
        .collection("users")
        .doc(uid)
        .collection("emergency_contacts")
        .get();

      const trustedEmails = new Set<string>();
      contacts.forEach((snapshot) => {
        const contact = snapshot.data() as ContactData;
        const email =
          typeof contact.email === "string"
            ? contact.email.trim().toLowerCase()
            : "";

        if (
          email &&
          contact.isActive !== false &&
          contact.emailVerified === true &&
          contact.consentStatus === "accepted"
        ) {
          trustedEmails.add(email);
        }
      });

      const [profileSnapshot, settingsSnapshot] = await Promise.all([
        db.collection("users").doc(uid).get(),
        db.collection("users").doc(uid).collection("settings").doc("checkin").get(),
      ]);
      const profile = profileSnapshot.data();
      const settings = settingsSnapshot.data();

      await db.collection("trustedStatuses").doc(uid).set(
        {
          ownerUid: uid,
          ownerName:
            typeof profile?.displayName === "string" &&
            profile.displayName.trim()
              ? profile.displayName.trim()
              : typeof profile?.email === "string" &&
                  profile.email.trim()
                ? profile.email.trim()
                : "Người cần theo dõi",
          relationship: "Người thân khẩn cấp",
          trustedEmails: [...trustedEmails],
          relationshipsUpdatedAt: FieldValue.serverTimestamp(),
          isDeadManSwitchActive: settings?.isDeadManSwitchActive !== false,
          lastCheckInAt:
            settings?.lastCheckInAt instanceof Timestamp
              ? settings.lastCheckInAt
              : null,
          nextCheckInDueAt:
            settings?.nextCheckInDueAt instanceof Timestamp
              ? settings.nextCheckInDueAt
              : null,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (error) {
      logger.error("Không thể đồng bộ trustedStatuses", {
        uid,
        error,
      });
      throw error;
    }
  }
);
