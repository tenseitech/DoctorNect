'use strict';

/**
 * mail_dispatcher.js
 *
 * Processes pending items from public.mail_queue and dispatches outbound emails
 * via MSG91 Email API proxy.
 */

const { sendMsg91Email } = require('./msg91_email');

async function processMailQueue({ supabase, sendEmail = sendMsg91Email, limit = 10 } = {}) {
  if (!supabase) {
    throw new Error('Supabase client is required for mail dispatcher');
  }

  const { data: pendingMails, error } = await supabase
    .from('mail_queue')
    .select('mail_id, to_address, subject, text_body, html_body, attempts')
    .eq('status', 'pending')
    .order('created_at', { ascending: true })
    .limit(limit);

  if (error) {
    console.error('[MailDispatcher] Error querying mail_queue:', error);
    return { success: false, error: error.message, processed: 0 };
  }

  if (!pendingMails || pendingMails.length === 0) {
    return { success: true, processed: 0, sent: 0, failed: 0 };
  }

  let sentCount = 0;
  let failedCount = 0;

  for (const mail of pendingMails) {
    try {
      const result = await sendEmail({
        toEmail: mail.to_address,
        subject: mail.subject,
        text: mail.text_body,
        html: mail.html_body,
      });

      await supabase
        .from('mail_queue')
        .update({
          status: 'sent',
          sent_at: new Date().toISOString(),
          attempts: (mail.attempts || 0) + 1,
        })
        .eq('mail_id', mail.mail_id);

      sentCount++;
    } catch (sendErr) {
      const attempts = (mail.attempts || 0) + 1;
      const finalStatus = attempts >= 3 ? 'failed' : 'pending';

      await supabase
        .from('mail_queue')
        .update({
          attempts,
          status: finalStatus,
          error_message: sendErr?.message || String(sendErr),
        })
        .eq('mail_id', mail.mail_id);

      failedCount++;
    }
  }

  return {
    success: true,
    processed: pendingMails.length,
    sent: sentCount,
    failed: failedCount,
  };
}

module.exports = {
  processMailQueue,
};
