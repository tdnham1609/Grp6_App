"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEFAULT_GRACE_PERIOD_MINUTES = void 0;
exports.evaluateDeadManSwitch = evaluateDeadManSwitch;
/**
 * Thời gian gia hạn an toàn mặc định (phút) trước khi kích hoạt cảnh báo
 * Cho phép người dùng thêm 3 giờ để sạc pin, kết nối mạng hoặc giải quyết chậm trễ
 */
exports.DEFAULT_GRACE_PERIOD_MINUTES = 180;
/**
 * Động cơ phân tích an toàn cốt lõi (Pure Safety Evaluation Engine)
 * Độc lập với Firebase, dễ dàng unit test 100% các tình huống biên
 */
function evaluateDeadManSwitch(params) {
    const { now, settings, existingAlert } = params;
    // 1. Kiểm tra tính năng có được bật hay không
    if (settings.isDeadManSwitchActive === false) {
        return {
            action: 'NO_ACTION',
            reason: 'Tính năng Dead Man Switch đang bị tắt bởi người dùng',
        };
    }
    // 2. Kiểm tra dữ liệu thời gian có hợp lệ không
    if (!settings.nextCheckInDueAt) {
        return {
            action: 'NO_ACTION',
            reason: 'Chưa có mốc thời gian hạn check-in tiếp theo',
        };
    }
    const dueDate = settings.nextCheckInDueAt.toDate();
    const lastCheckInDate = settings.lastCheckInAt
        ? settings.lastCheckInAt.toDate()
        : null;
    // 3. Nếu ĐÃ CÓ sự kiện cảnh báo trước đó và chưa bị huỷ
    if (existingAlert && existingAlert.status !== 'cancelled') {
        const alertDueDate = existingAlert.checkInDueAt.toDate();
        // KIỂM TRA HUỶ: Người dùng đã check-in an toàn trở lại (lastCheckIn mới hơn mốc quá hạn)
        if (lastCheckInDate && lastCheckInDate > alertDueDate) {
            return {
                action: 'CANCEL_ALERT',
                reason: 'Người dùng đã check-in an toàn trở lại sau thời điểm quá hạn',
                targetStatus: 'cancelled',
            };
        }
        // Hoặc hạn tiếp theo đã được dời về tương lai
        if (dueDate > now) {
            return {
                action: 'CANCEL_ALERT',
                reason: 'Hạn check-in đã được cập nhật về tương lai',
                targetStatus: 'cancelled',
            };
        }
        // Nếu cảnh báo đã được gửi hoặc đã dry-run thì không kích hoạt lại (chống lặp vô hạn)
        if (existingAlert.status === 'dry_run_dispatched' ||
            existingAlert.status === 'alert_sent') {
            return {
                action: 'NO_ACTION',
                reason: `Cảnh báo đã được xử lý trước đó (trạng thái: ${existingAlert.status}); bảo đảm tính duy nhất (idempotency)`,
            };
        }
        // Kiểm tra thời gian gia hạn (Grace Period)
        const gracePeriodEnds = existingAlert.gracePeriodEndsAt.toDate();
        if (now < gracePeriodEnds) {
            return {
                action: 'NO_ACTION',
                reason: `Người dùng đang trong thời gian gia hạn an toàn (hết hạn lúc ${gracePeriodEnds.toISOString()})`,
                gracePeriodEndsAt: gracePeriodEnds,
            };
        }
        // Đã hết thời gian gia hạn -> Kích hoạt Dry-Run cảnh báo
        return {
            action: 'TRIGGER_DRY_RUN',
            reason: 'Thời gian gia hạn an toàn đã kết thúc. Đủ điều kiện kích hoạt cảnh báo khẩn cấp (Dry-Run)',
            targetStatus: 'dry_run_dispatched',
        };
    }
    // 4. Nếu CHƯA CÓ sự kiện cảnh báo (hoặc sự kiện cũ đã được giải quyết)
    // Nếu vẫn còn trong hạn an toàn -> Không làm gì
    if (now <= dueDate) {
        return {
            action: 'NO_ACTION',
            reason: 'Người dùng vẫn đang trong thời hạn check-in an toàn',
        };
    }
    // Người dùng đã quá hạn! Tính mốc kết thúc thời gian gia hạn
    const graceMinutes = typeof settings.gracePeriodMinutes === 'number' && settings.gracePeriodMinutes > 0
        ? settings.gracePeriodMinutes
        : exports.DEFAULT_GRACE_PERIOD_MINUTES;
    const gracePeriodEnds = new Date(dueDate.getTime() + graceMinutes * 60 * 1000);
    // Nếu vẫn trong thời gian gia hạn -> Bắt đầu ghi nhận trạng thái 'overdue'
    if (now < gracePeriodEnds) {
        return {
            action: 'START_GRACE_PERIOD',
            reason: `Quá hạn check-in lúc ${dueDate.toISOString()}. Bắt đầu đếm ngược thời gian gia hạn an toàn ${graceMinutes} phút`,
            targetStatus: 'overdue',
            gracePeriodEndsAt: gracePeriodEnds,
        };
    }
    // Nếu khi quét lần đầu mà đã vượt qua cả thời gian gia hạn -> Kích hoạt Dry-Run
    return {
        action: 'TRIGGER_DRY_RUN',
        reason: 'Đã quá hạn check-in và vượt qua cả thời gian gia hạn an toàn',
        targetStatus: 'dry_run_dispatched',
        gracePeriodEndsAt: gracePeriodEnds,
    };
}
//# sourceMappingURL=safetyEngine.js.map