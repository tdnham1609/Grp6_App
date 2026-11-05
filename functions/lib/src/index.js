"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncTrustedStatus = exports.verifyContactPortal = exports.requestContactVerification = exports.sendDemoAlert = exports.runOverdueDemoCheck = exports.checkOverdueDeadManSwitch = void 0;
const app_1 = require("firebase-admin/app");
// Khởi tạo Firebase Admin SDK trên máy chủ Cloud Functions
(0, app_1.initializeApp)();
// Export scheduled Cloud Function
var checkOverdueDeadManSwitch_1 = require("./checkOverdueDeadManSwitch");
Object.defineProperty(exports, "checkOverdueDeadManSwitch", { enumerable: true, get: function () { return checkOverdueDeadManSwitch_1.checkOverdueDeadManSwitch; } });
var checkOverdueDeadManSwitch_2 = require("./checkOverdueDeadManSwitch");
Object.defineProperty(exports, "runOverdueDemoCheck", { enumerable: true, get: function () { return checkOverdueDeadManSwitch_2.runOverdueDemoCheck; } });
// Explicit, clearly labeled demo email (sent only to opted-in contacts).
var demoAlert_1 = require("./demoAlert");
Object.defineProperty(exports, "sendDemoAlert", { enumerable: true, get: function () { return demoAlert_1.sendDemoAlert; } });
// Export Contact Verification & Consent Cloud Functions
var contactVerification_1 = require("./contactVerification");
Object.defineProperty(exports, "requestContactVerification", { enumerable: true, get: function () { return contactVerification_1.requestContactVerification; } });
Object.defineProperty(exports, "verifyContactPortal", { enumerable: true, get: function () { return contactVerification_1.verifyContactPortal; } });
var trustedStatusSync_1 = require("./trustedStatusSync");
Object.defineProperty(exports, "syncTrustedStatus", { enumerable: true, get: function () { return trustedStatusSync_1.syncTrustedStatus; } });
//# sourceMappingURL=index.js.map