const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const nodemailer = require("nodemailer");

initializeApp();

const EMAIL_USER = defineSecret("EMAIL_USER");
const EMAIL_PASS = defineSecret("EMAIL_PASS");

const db = getFirestore();

// Configure email transport using environment variables set via:
//   firebase functions:secrets:set EMAIL_HOST EMAIL_PORT EMAIL_USER EMAIL_PASS
// or via Firebase Functions config (v1 style):
//   firebase functions:config:set email.host="smtp.gmail.com" ...
function createTransport() {
  return nodemailer.createTransport({
    host: "smtp.gmail.com",
    port: 587,
    secure: false,
    auth: {
      user: EMAIL_USER.value(),
      pass: EMAIL_PASS.value(),
    },
  });
}

function buildEmailHtml({ shopName, rating, comment, submittedAt, dashboardUrl }) {
  const stars = "★".repeat(rating) + "☆".repeat(5 - rating);
  const commentHtml = comment
    ? `<p style="margin:0 0 12px;color:#374151;font-size:15px;">${escapeHtml(comment)}</p>`
    : `<p style="margin:0 0 12px;color:#9CA3AF;font-size:14px;font-style:italic;">No comment provided</p>`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>New Customer Feedback – ${escapeHtml(shopName)}</title>
</head>
<body style="margin:0;padding:0;background:#F3F4F6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#F3F4F6;padding:32px 16px;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#FFFFFF;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.08);">

        <!-- Header -->
        <tr>
          <td style="background:#16A34A;padding:28px 32px;text-align:center;">
            <p style="margin:0 0 4px;color:rgba(255,255,255,0.75);font-size:12px;letter-spacing:1.5px;text-transform:uppercase;">ReviewQR</p>
            <h1 style="margin:0;color:#FFFFFF;font-size:22px;font-weight:700;">New Customer Feedback</h1>
          </td>
        </tr>

        <!-- Body -->
        <tr>
          <td style="padding:28px 32px;">
            <p style="margin:0 0 18px;color:#374151;font-size:15px;">
              <strong>${escapeHtml(shopName)}</strong> received new feedback.
            </p>

            <!-- Rating card -->
            <table width="100%" cellpadding="0" cellspacing="0" style="background:#F0FDF4;border-radius:10px;margin-bottom:20px;">
              <tr>
                <td style="padding:18px 20px;">
                  <p style="margin:0 0 4px;color:#6B7280;font-size:12px;text-transform:uppercase;letter-spacing:1px;">Rating</p>
                  <p style="margin:0;color:#16A34A;font-size:26px;letter-spacing:2px;">${stars}</p>
                  <p style="margin:4px 0 0;color:#374151;font-size:14px;font-weight:600;">${rating} out of 5</p>
                </td>
              </tr>
            </table>

            <!-- Feedback message -->
            <p style="margin:0 0 6px;color:#6B7280;font-size:12px;text-transform:uppercase;letter-spacing:1px;">Feedback</p>
            ${commentHtml}

            <!-- Meta -->
            <p style="margin:16px 0 6px;color:#6B7280;font-size:12px;text-transform:uppercase;letter-spacing:1px;">Submitted</p>
            <p style="margin:0 0 24px;color:#374151;font-size:14px;">${escapeHtml(submittedAt)}</p>

            <!-- CTA -->
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td align="center">
                  <a href="${dashboardUrl}" style="display:inline-block;background:#16A34A;color:#FFFFFF;font-size:14px;font-weight:600;text-decoration:none;padding:12px 28px;border-radius:8px;">
                    View Dashboard
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- Footer -->
        <tr>
          <td style="padding:16px 32px 24px;border-top:1px solid #E5E7EB;text-align:center;">
            <p style="margin:0;color:#9CA3AF;font-size:12px;">
              You are receiving this because email notifications are enabled for <strong>${escapeHtml(shopName)}</strong>.
              Log in to your ReviewQR dashboard to manage notification settings.
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * Triggered whenever a new document is created in the feedback collection.
 * Reads the shop's notification settings, and if enabled, sends an email.
 * Updates emailNotificationStatus on the feedback doc to 'sent' or 'failed'.
 * Never throws so feedback submission is never blocked.
 */
exports.sendFeedbackEmailNotification = onDocumentCreated(
  { document: "feedback/{feedbackId}", secrets: [EMAIL_USER, EMAIL_PASS] },
  async (event) => {
    const feedbackId = event.params.feedbackId;
    const feedback = event.data?.data();
    if (!feedback) return;

    const { shopId, rating, comment, createdAt } = feedback;
    const feedbackRef = db.collection("feedback").doc(feedbackId);

    try {
      const shopSnap = await db.collection("shops").doc(shopId).get();
      if (!shopSnap.exists) {
        await feedbackRef.update({ emailNotificationStatus: "no_shop" });
        return;
      }

      const shop = shopSnap.data();
      if (!shop.emailNotificationsEnabled || !shop.notificationEmail) {
        await feedbackRef.update({ emailNotificationStatus: "disabled" });
        return;
      }

      const submittedAt = createdAt?.toDate
        ? createdAt.toDate().toLocaleString("en-US", { timeZone: "UTC" }) + " UTC"
        : new Date().toUTCString();

      const dashboardUrl = "https://reviewqr.web.app";

      const transport = createTransport();
      await transport.sendMail({
        from: `"ReviewQR" <${EMAIL_USER.value()}>`,
        to: shop.notificationEmail,
        subject: `New Customer Feedback – ${shop.shopName}`,
        html: buildEmailHtml({
          shopName: shop.shopName,
          rating,
          comment,
          submittedAt,
          dashboardUrl,
        }),
      });

      await feedbackRef.update({
        emailNotificationStatus: "sent",
        emailSentAt: FieldValue.serverTimestamp(),
      });
    } catch (err) {
      console.error("sendFeedbackEmailNotification error:", err);
      try {
        await feedbackRef.update({ emailNotificationStatus: "failed" });
      } catch (_) {}
    }
  }
);
