import * as nodemailer from 'nodemailer';
import * as logger from 'firebase-functions/logger';
import { maskEmail } from './verificationEngine';
import { AlertLocationData, AlertRecipientRecord } from './types';

/**
 * Tuỳ chọn gửi email
 */
export interface SendEmailOptions {
  to: string;
  from?: string;
  subject: string;
  html: string;
  text: string;
}

/**
 * Kết quả gửi của Transport
 */
export interface TransportResult {
  success: boolean;
  messageId?: string;
  error?: string;
}

export interface SendContactVerificationEmailParams {
  recipientEmail: string;
  contactName: string;
  userName: string;
  verificationUrl: string;
  expiresAt: Date;
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => {
    const entities: Record<string, string> = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;',
    };
    return entities[character];
  });
}

/**
 * Interface trừu tượng cho tầng vận chuyển email (dễ dàng mock trong unit test)
 */
export interface EmailTransport {
  sendMail(options: SendEmailOptions): Promise<TransportResult>;
}

/**
 * Transport triển khai bằng Nodemailer (SMTP thực tế)
 */
export class NodemailerTransport implements EmailTransport {
  private transporter: nodemailer.Transporter;
  private fromAddress: string;

  constructor(config: {
    host: string;
    port: number;
    secure: boolean;
    auth: {
      user: string;
      pass: string;
    };
    from: string;
  }) {
    this.fromAddress = config.from;
    this.transporter = nodemailer.createTransport({
      host: config.host,
      port: config.port,
      secure: config.secure,
      auth: {
        user: config.auth.user,
        pass: config.auth.pass,
      },
      connectionTimeout: 8000, // 8 giây timeout kết nối
      socketTimeout: 10000,    // 10 giây timeout truyền dữ liệu
    });
  }

  async sendMail(options: SendEmailOptions): Promise<TransportResult> {
    try {
      const info = await this.transporter.sendMail({
        from: options.from || this.fromAddress,
        to: options.to,
        subject: options.subject,
        text: options.text,
        html: options.html,
      });

      return {
        success: true,
        messageId: info.messageId,
      };
    } catch (err: any) {
      return {
        success: false,
        error: err?.message || 'Lỗi không xác định khi gửi email qua SMTP',
      };
    }
  }
}

/**
 * Transport Mock dùng cho kiểm thử tự động / Sandbox mà không gọi ra Internet
 */
export class MockEmailTransport implements EmailTransport {
  public sentMails: SendEmailOptions[] = [];
  public shouldFail: boolean = false;
  public failureMessage: string = 'Lỗi mô phỏng từ MockEmailTransport';

  async sendMail(options: SendEmailOptions): Promise<TransportResult> {
    if (this.shouldFail) {
      return {
        success: false,
        error: this.failureMessage,
      };
    }
    this.sentMails.push(options);
    return {
      success: true,
      messageId: `mock_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`,
    };
  }

  clear(): void {
    this.sentMails = [];
    this.shouldFail = false;
  }
}

/**
 * Tham số gửi email cảnh báo tới 1 người nhận
 */
export interface SendAlertEmailParams {
  recipient: {
    contactId: string;
    email: string;
    name: string;
  };
  userName: string;
  dueDate: Date;
  gracePeriodEndsAt: Date;
  location?: AlertLocationData | null;
  revokeConsentUrl?: string;
  isDemo?: boolean;
}

/**
 * Service điều phối gửi email cảnh báo an toàn
 */
export class EmailService {
  private transport?: EmailTransport;
  private isRealAlertsEnabled: boolean;

  constructor(transport?: EmailTransport) {
    this.transport = transport;
    // BẮT BUỘC: Mặc định luôn là false trừ khi biến môi trường được đặt rõ ràng là 'true'
    this.isRealAlertsEnabled = process.env.SEND_REAL_ALERTS === 'true';
  }

  /**
   * Kiểm tra xem cấu hình gửi email thật có đầy đủ và hợp lệ hay không
   */
  public hasValidConfiguration(isDemo = false): boolean {
    const sendingEnabled = isDemo
      ? process.env.SEND_DEMO_ALERTS === 'true'
      : this.isRealAlertsEnabled;
    if (!sendingEnabled) {
      return false;
    }

    const host = process.env.SMTP_HOST;
    const port = process.env.SMTP_PORT;
    const user = process.env.SMTP_USER;
    const pass = process.env.SMTP_PASS;
    const from = process.env.SMTP_FROM;

    return Boolean(host && port && user && pass && from);
  }

  /**
   * Lấy hoặc khởi tạo Transport phù hợp
   */
  private getTransport(isDemo = false): EmailTransport | null {
    if (this.transport) {
      return this.transport;
    }

    if (!this.hasValidConfiguration(isDemo)) {
      return null;
    }

    const host = process.env.SMTP_HOST!;
    const port = parseInt(process.env.SMTP_PORT || '587', 10);
    const secure = port === 465;
    const user = process.env.SMTP_USER!;
    const pass = process.env.SMTP_PASS!;
    const from = process.env.SMTP_FROM!;

    this.transport = new NodemailerTransport({
      host,
      port,
      secure,
      auth: { user, pass },
      from,
    });

    return this.transport;
  }

  /** Send a verification and opt-in link while demo email delivery is enabled. */
  public async sendContactVerificationEmail(
    params: SendContactVerificationEmailParams,
  ): Promise<TransportResult> {
    const masked = maskEmail(params.recipientEmail);
    if (!this.hasValidConfiguration(true)) {
      logger.info(`[VerificationEmail][DRY-RUN] Không gửi email xác minh tới ${masked}.`);
      return { success: false, error: 'Email demo chưa được cấu hình.' };
    }

    const transport = this.getTransport(true);
    if (!transport) {
      return { success: false, error: 'Không khởi tạo được SMTP transport.' };
    }

    const safeContactName = escapeHtml(params.contactName);
    const safeUserName = escapeHtml(params.userName);
    const safeUrl = escapeHtml(params.verificationUrl);
    const expiresAt = params.expiresAt.toLocaleString('vi-VN', {
      timeZone: 'Asia/Ho_Chi_Minh',
    });
    const subject = '[Sinh Tử] Xác minh email liên hệ khẩn cấp';
    const text = [
      `Xin chào ${params.contactName},`,
      '',
      `${params.userName} đã thêm bạn làm liên hệ khẩn cấp trong ứng dụng Sinh Tử.`,
      'Mở liên kết bên dưới để xác minh địa chỉ email và chọn có đồng ý nhận cảnh báo hay không.',
      'Bạn chỉ nhận cảnh báo khẩn cấp nếu chủ động chọn đồng ý trên trang xác minh.',
      '',
      params.verificationUrl,
      '',
      `Liên kết hết hạn lúc ${expiresAt}.`,
      '',
      'Nếu bạn không mong đợi email này, bạn có thể bỏ qua.',
      'Hệ thống An Toàn Sinh Tử',
    ].join('\n');
    const html = `
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"><title>Xác minh liên hệ Sinh Tử</title></head>
      <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #1e293b; background: #f8fafc; padding: 24px;">
        <div style="max-width: 580px; margin: 0 auto; background: white; border-radius: 12px; padding: 28px; border: 1px solid #e2e8f0;">
          <h2 style="color: #082f49;">Xác minh liên hệ khẩn cấp</h2>
          <p>Xin chào <strong>${safeContactName}</strong>,</p>
          <p><strong>${safeUserName}</strong> đã thêm bạn làm liên hệ khẩn cấp trong ứng dụng Sinh Tử.</p>
          <p>Mở liên kết để xác minh email và chọn có đồng ý nhận cảnh báo hay không. Bạn chỉ nhận cảnh báo nếu chủ động chấp thuận.</p>
          <p style="margin: 24px 0;">
            <a href="${safeUrl}" style="display: inline-block; padding: 12px 18px; border-radius: 8px; background: #078d83; color: white; text-decoration: none; font-weight: 700;">Xác minh và chọn đồng ý</a>
          </p>
          <p style="font-size: 13px; color: #64748b;">Liên kết hết hạn lúc ${expiresAt}.</p>
          <p style="font-size: 13px; color: #64748b;">Nếu bạn không mong đợi email này, bạn có thể bỏ qua.</p>
        </div>
      </body>
      </html>
    `;

    let lastError = 'Không gửi được email xác minh.';
    for (let attempt = 1; attempt <= 2; attempt++) {
      const result = await transport.sendMail({
        to: params.recipientEmail,
        subject,
        text,
        html,
      });
      if (result.success) {
        logger.info(`[VerificationEmail] Đã gửi link xác minh tới ${masked}.`);
        return result;
      }
      lastError = result.error || lastError;
      if (attempt < 2) await new Promise((resolve) => setTimeout(resolve, 1000));
    }

    logger.warn(`[VerificationEmail] Gửi email tới ${masked} thất bại: ${lastError}`);
    return { success: false, error: lastError };
  }

  /**
   * Tạo nội dung text cho email cảnh báo
   */
  public buildEmailText(params: SendAlertEmailParams): string {
    const { recipient, userName, dueDate, gracePeriodEndsAt, location, revokeConsentUrl } = params;

    if (params.isDemo) {
      const demoLocationLines = location?.isSharingEnabled
        ? [
            '',
            'VỊ TRÍ ĐƯỢC CHIA SẺ:',
            location.address
              ? `- Địa chỉ gần nhất (ước tính): ${location.address}`
              : '- Chưa tra được địa chỉ gần nhất; xem vị trí theo toạ độ bên dưới.',
            `- Toạ độ: ${location.latitude.toFixed(5)}, ${location.longitude.toFixed(5)}`,
            ...(location.accuracy ? [`- Độ chính xác GPS: khoảng ${location.accuracy.toFixed(0)} m`] : []),
            ...(location.timestamp ? [`- Thời điểm ghi nhận: ${this.formatLocationTimestamp(location.timestamp)}`] : []),
            `- Bản đồ: https://www.google.com/maps?q=${location.latitude},${location.longitude}`,
            ...(location.address ? ['- Nguồn địa chỉ: © OpenStreetMap contributors (openstreetmap.org/copyright)'] : []),
          ]
        : [];
      return [
        `Kính gửi ${recipient.name},`,
        '',
        '[EMAIL DEMO — KHÔNG PHẢI CẢNH BÁO KHẨN CẤP THẬT]',
        '',
        `Người dùng "${userName}" vừa chủ động gửi email thử nghiệm từ ứng dụng Sinh Tử lúc ${dueDate.toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' })}.`,
        'Email này dùng để trình diễn luồng cảnh báo và kiểm tra gửi email. Bạn không cần thực hiện hành động khẩn cấp.',
        ...demoLocationLines,
        '',
        'Trân trọng,',
        'Hệ thống An Toàn Sinh Tử.',
      ].join('\n');
    }

    let text = `Kính gửi ${recipient.name},\n\n`;
    text += `Đây là thông báo an toàn tự động từ hệ thống Sinh Tử (Dead Man's Switch).\n\n`;
    text += `Người dùng "${userName}" đã đăng ký bạn là Người Liên Hệ Khẩn Cấp và bạn đã chấp thuận nhận thông báo này trước đó.\n\n`;
    text += `THÔNG TIN CẢNH BÁO:\n`;
    text += `- Mốc thời hạn xác nhận an toàn: ${dueDate.toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' })}\n`;
    text += `- Thời gian gia hạn an toàn đã kết thúc lúc: ${gracePeriodEndsAt.toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' })}\n`;
    text += `- Tình trạng: Hệ thống chưa nhận được tín hiệu xác nhận an toàn sau khi đã hết thời gian gia hạn.\n\n`;

    if (location && location.isSharingEnabled) {
      text += `THÔNG TIN ĐỊNH VỊ GẦN NHẤT:\n`;
      text += location.address
        ? `- Địa chỉ gần nhất (ước tính): ${location.address}\n- Nguồn địa chỉ: © OpenStreetMap contributors (openstreetmap.org/copyright)\n`
        : `- Chưa tra được địa chỉ gần nhất; hãy mở bản đồ theo toạ độ bên dưới.\n`;
      text += `- Toạ độ: ${location.latitude.toFixed(5)}, ${location.longitude.toFixed(5)}\n`;
      if (location.accuracy) {
        text += `- Độ chính xác: ~${location.accuracy.toFixed(0)}m\n`;
      }
      if (location.timestamp) {
        text += `- Thời điểm ghi nhận vị trí lần cuối: ${this.formatLocationTimestamp(location.timestamp)}\n`;
      }
      text += `- Bản đồ: https://www.google.com/maps?q=${location.latitude},${location.longitude}\n\n`;
    } else {
      text += `THÔNG TIN ĐỊNH VỊ: Người dùng không bật chia sẻ toạ độ GPS hoặc không có toạ độ khả dụng.\n\n`;
    }

    text += `Vui lòng liên lạc ngay với ${userName} qua số điện thoại hoặc các kênh liên lạc cá nhân để kiểm tra tình hình.\n\n`;

    if (revokeConsentUrl) {
      text += `Nếu bạn không còn muốn nhận cảnh báo từ người này, bạn có thể thu hồi sự đồng ý tại: ${revokeConsentUrl}\n\n`;
    }

    text += `Trân trọng,\nHệ thống An Toàn Sinh Tử.`;
    return text;
  }

  private formatLocationTimestamp(ts: unknown): string {
    if (!ts) return '';
    if (ts instanceof Date) return ts.toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' });
    if (ts && typeof (ts as { toDate?: () => Date }).toDate === 'function') {
      return (ts as { toDate: () => Date }).toDate().toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' });
    }
    return new Date(String(ts)).toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' });
  }

  /**
   * Tạo nội dung HTML chuẩn cho email cảnh báo
   */
  public buildEmailHtml(params: SendAlertEmailParams): string {
    const { recipient, userName, dueDate, gracePeriodEndsAt, location, revokeConsentUrl } = params;

    if (params.isDemo) {
      const sentAt = dueDate.toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' });
      const demoLocationHtml = location?.isSharingEnabled
        ? `
          <div style="background:#ecfdf5;border:1px solid #a7f3d0;border-radius:8px;padding:14px;margin:16px 0;">
            <strong style="color:#065f46;">📍 Vị trí được chia sẻ</strong>
            ${location.address
              ? `<p style="margin:6px 0;color:#047857;">Địa chỉ gần nhất (ước tính): <strong>${escapeHtml(location.address)}</strong></p><p style="margin:0 0 6px;color:#64748b;font-size:12px;">© <a href="https://www.openstreetmap.org/copyright" style="color:#64748b;">OpenStreetMap contributors</a></p>`
              : '<p style="color:#64748b;">Chưa tra được địa chỉ gần nhất; có thể xem vị trí theo toạ độ.</p>'}
            <p style="margin:4px 0;color:#047857;font-size:13px;">Toạ độ: ${location.latitude.toFixed(5)}, ${location.longitude.toFixed(5)}${location.accuracy ? ` (sai số khoảng ${location.accuracy.toFixed(0)} m)` : ''}</p>
            ${location.timestamp ? `<p style="margin:4px 0;color:#64748b;font-size:12px;">Ghi nhận lúc: ${this.formatLocationTimestamp(location.timestamp)}</p>` : ''}
            <a href="https://www.google.com/maps?q=${location.latitude},${location.longitude}" style="color:#047857;">Mở Google Maps</a>
          </div>
        `
        : '';
      return `
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>Email demo Sinh Tử</title></head>
        <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #1e293b; background: #f8fafc; padding: 24px;">
          <div style="max-width: 580px; margin: 0 auto; background: white; border-radius: 12px; padding: 28px; border: 1px solid #e2e8f0;">
            <div style="background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 8px; padding: 12px; color: #1d4ed8; font-weight: 700;">
              EMAIL DEMO — KHÔNG PHẢI CẢNH BÁO KHẨN CẤP THẬT
            </div>
            <p>Kính gửi <strong>${recipient.name}</strong>,</p>
            <p><strong>${userName}</strong> vừa chủ động gửi email thử nghiệm từ ứng dụng Sinh Tử lúc ${sentAt}.</p>
            <p>Email này dùng để trình diễn luồng cảnh báo và kiểm tra gửi email. Bạn không cần thực hiện hành động khẩn cấp.</p>
            ${demoLocationHtml}
            <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 24px 0;">
            <p style="color: #64748b; font-size: 13px;">Hệ thống An Toàn Sinh Tử</p>
          </div>
        </body>
        </html>
      `;
    }

    const dueFormatted = dueDate.toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' });
    const graceFormatted = gracePeriodEndsAt.toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' });

    let locationHtml = `
      <div style="background-color: #f1f5f9; border-radius: 8px; padding: 14px; margin: 16px 0;">
        <strong style="color: #475569;">Toạ độ định vị:</strong>
        <p style="margin: 4px 0 0 0; color: #64748b; font-size: 13px;">Người dùng không bật chia sẻ toạ độ GPS hoặc không có toạ độ khả dụng.</p>
      </div>
    `;

    if (location && location.isSharingEnabled) {
      const mapsUrl = `https://www.google.com/maps?q=${location.latitude},${location.longitude}`;
      const addressHtml = location.address
        ? `<p style="margin:4px 0;color:#047857;">Địa chỉ gần nhất (ước tính): <strong>${escapeHtml(location.address)}</strong></p><p style="margin:0 0 6px;color:#64748b;font-size:12px;">© <a href="https://www.openstreetmap.org/copyright" style="color:#64748b;">OpenStreetMap contributors</a></p>`
        : '<p style="margin:4px 0;color:#64748b;">Chưa tra được địa chỉ gần nhất; hãy mở bản đồ theo toạ độ bên dưới.</p>';
      let timeDetail = '';
      if (location.timestamp) {
        timeDetail = `<p style="margin: 3px 0 6px 0; color: #065f46; font-size: 13px;">Thời điểm ghi nhận vị trí lần cuối: <strong>${this.formatLocationTimestamp(location.timestamp)}</strong></p>`;
      }
      locationHtml = `
        <div style="background-color: #ecfdf5; border: 1px solid #a7f3d0; border-radius: 8px; padding: 14px; margin: 16px 0;">
          <strong style="color: #065f46;">📍 Toạ độ ghi nhận gần nhất của người dùng:</strong>
          ${addressHtml}
          <p style="margin: 4px 0 4px 0; color: #047857; font-size: 13.5px;">
            Vĩ độ: <strong>${location.latitude.toFixed(5)}</strong>, Kinh độ: <strong>${location.longitude.toFixed(5)}</strong>
            ${location.accuracy ? ` (Độ chính xác: ~${location.accuracy.toFixed(0)}m)` : ''}
          </p>
          ${timeDetail}
          <div style="margin-top: 10px;">
            <a href="${mapsUrl}" target="_blank" style="display: inline-block; padding: 7px 14px; background-color: #059669; color: white; text-decoration: none; border-radius: 6px; font-size: 13px; font-weight: 600;">Xem trên Google Maps →</a>
          </div>
        </div>
      `;
    }

    return `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Cảnh báo an toàn Sinh Tử</title>
      </head>
      <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #1e293b; background-color: #f8fafc; margin: 0; padding: 24px;">
        <div style="max-width: 580px; margin: 0 auto; background-color: #ffffff; border-radius: 12px; padding: 28px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); border: 1px solid #e2e8f0;">
          <div style="border-bottom: 2px solid #e2e8f0; padding-bottom: 16px; margin-bottom: 20px;">
            <h2 style="color: #b91c1c; margin: 0; font-size: 20px;">⚠️ CẢNH BÁO AN TOÀN SINH TỬ</h2>
            <p style="margin: 4px 0 0 0; color: #64748b; font-size: 13px;">Thông báo khẩn cấp từ hệ thống Dead Man's Switch</p>
          </div>

          <p>Kính gửi <strong>${recipient.name}</strong>,</p>

          <p>Hệ thống tự động ghi nhận tài khoản của <strong>${userName}</strong> đã không thực hiện xác nhận an toàn theo chu kỳ đã thiết lập.</p>

          <div style="background-color: #fef2f2; border: 1px solid #fecaca; border-radius: 8px; padding: 14px; margin: 16px 0;">
            <ul style="margin: 0; padding-left: 20px; color: #991b1b; font-size: 13.5px;">
              <li><strong>Hạn điểm danh an toàn:</strong> ${dueFormatted}</li>
              <li><strong>Thời gian gia hạn an toàn đã hết lúc:</strong> ${graceFormatted}</li>
            </ul>
          </div>

          ${locationHtml}

          <p style="color: #334155; font-size: 14px;">
            Bạn nhận được email này vì đã được <strong>${userName}</strong> đăng ký và bạn đã chủ động chấp thuận làm người nhận cảnh báo khẩn cấp.
            <strong>Vui lòng chủ động liên lạc với người thân ngay để kiểm tra tình hình.</strong>
          </p>

          <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0 16px 0;">

          ${revokeConsentUrl ? `
            <p style="font-size: 12px; color: #94a3b8; margin: 0;">
              Nếu bạn không muốn tiếp tục nhận cảnh báo, bạn có thể <a href="${revokeConsentUrl}" style="color: #64748b; text-decoration: underline;">thu hồi quyền nhận tin tại đây</a>.
            </p>
          ` : ''}
        </div>
      </body>
      </html>
    `;
  }

  /**
   * Gửi email cảnh báo tới một người nhận với retry có giới hạn (tối đa 2 lần)
   */
  public async sendAlertEmail(params: SendAlertEmailParams): Promise<AlertRecipientRecord> {
    const { recipient } = params;
    const masked = maskEmail(recipient.email);

    // 1. Kiểm tra chế độ Dry-Run hoặc thiếu cấu hình
    const isDemo = params.isDemo === true;
    if (!this.hasValidConfiguration(isDemo)) {
      logger.info(
        `[EmailService][DRY-RUN] Bỏ qua gửi email thật tới ${masked} (contactId: ${recipient.contactId}). Chế độ Dry-Run đang bật.`
      );
      return {
        contactId: recipient.contactId,
        email: recipient.email,
        name: recipient.name,
        status: 'skipped_dry_run',
        sentAt: null,
        error: null,
        attempts: 0,
      };
    }

    const transport = this.getTransport(isDemo);
    if (!transport) {
      return {
        contactId: recipient.contactId,
        email: recipient.email,
        name: recipient.name,
        status: 'failed',
        sentAt: null,
        error: 'Thiếu cấu hình SMTP transport',
        attempts: 0,
      };
    }

    const subject = params.isDemo
      ? `[DEMO] Kiểm tra luồng cảnh báo Sinh Tử từ ${params.userName}`
      : `[CẢNH BÁO AN TOÀN] Không nhận được phản hồi từ ${params.userName}`;
    const text = this.buildEmailText(params);
    const html = this.buildEmailHtml(params);

    // Chuẩn hoá tên người gửi và người nhận theo dữ liệu đã nhập và xác minh trên App
    const senderFrom = `"${params.userName.replace(/"/g, '')} (qua Hệ thống Sinh Tử)" <${process.env.SMTP_FROM || 'alert@sinhtu.app'}>`;
    const recipientTo = recipient.name
      ? `"${recipient.name.replace(/"/g, '')}" <${recipient.email}>`
      : recipient.email;

    const maxAttempts = 2;
    let lastError: string | null = null;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        logger.info(
          `[EmailService] Đang gửi email cảnh báo tới ${masked} (Lần thử ${attempt}/${maxAttempts})...`
        );

        const result = await transport.sendMail({
          to: recipientTo,
          from: senderFrom,
          subject,
          text,
          html,
        });

        if (result.success) {
          logger.info(
            `[EmailService] Gửi email thành công tới ${masked} (MessageId: ${result.messageId}).`
          );
          return {
            contactId: recipient.contactId,
            email: recipient.email,
            name: recipient.name,
            status: 'sent',
            sentAt: null, // Sẽ được caller gán Timestamp.now()
            error: null,
            attempts: attempt,
          };
        } else {
          lastError = result.error || 'Lỗi từ email transport';
          logger.warn(
            `[EmailService] Gửi email thất bại lần ${attempt} tới ${masked}: ${lastError}`
          );
        }
      } catch (err: any) {
        lastError = err?.message || 'Lỗi ngoại lệ khi gửi email';
        logger.warn(
          `[EmailService] Ngoại lệ khi gửi email lần ${attempt} tới ${masked}: ${lastError}`
        );
      }

      // Đợi 1 giây trước khi retry nếu còn lượt thử
      if (attempt < maxAttempts) {
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    }

    return {
      contactId: recipient.contactId,
      email: recipient.email,
      name: recipient.name,
      status: 'failed',
      sentAt: null,
      error: lastError,
      attempts: maxAttempts,
    };
  }
}
