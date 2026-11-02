import { initializeApp } from 'firebase-admin/app';

// Khởi tạo Firebase Admin SDK trên máy chủ Cloud Functions
initializeApp();

// Export scheduled Cloud Function
export { checkOverdueDeadManSwitch } from './checkOverdueDeadManSwitch';
export { runOverdueDemoCheck } from './checkOverdueDeadManSwitch';

// Explicit, clearly labeled demo email (sent only to opted-in contacts).
export { sendDemoAlert } from './demoAlert';

// Export Contact Verification & Consent Cloud Functions
export {
  requestContactVerification,
  verifyContactPortal,
} from './contactVerification';
