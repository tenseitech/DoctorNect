const https = require('https');

/**
 * Sends an email using MSG91 Email API v5.
 *
 * @param {Object} options
 * @param {string} options.toEmail - Recipient email address
 * @param {string} [options.recipientName] - Recipient name
 * @param {string} options.templateId - MSG91 template ID
 * @param {Object} [options.variables] - Map of template variables (e.g. { NAME: '...', ROLE: '...' })
 * @param {string} [options.fromEmail] - Sender email (defaults to no-reply@mail.doctornect.com)
 * @param {string} [options.domain] - Sender domain (defaults to mail.doctornect.com)
 */
async function sendMsg91Email({
  toEmail,
  subject,
}) {
  console.info(`[MSG91 Email] Outbound emails are globally disabled. Suppressed email dispatch to ${toEmail} (${subject}).`);
  return { success: true, skipped: true, disabled: true };
}

module.exports = { sendMsg91Email };
