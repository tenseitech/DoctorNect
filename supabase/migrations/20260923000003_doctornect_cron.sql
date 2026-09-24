-- ============================================================================
-- DOCTORNECT PLATFORM — SCHEDULED BACKGROUND TASKS (pg_cron)
-- ============================================================================
-- Description: Automated maintenance jobs for ad expiration and transient table cleanup.
-- ============================================================================

-- Enable pg_cron extension (standard in Supabase projects)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 1. Hourly job to expire completed promotional campaigns
SELECT cron.schedule(
    'expire-promoted-ads',
    '0 * * * *',
    $$
        UPDATE promoted_ads
        SET status = 'expired',
            updated_at = CURRENT_TIMESTAMP
        WHERE status = 'active'
          AND end_time <= CURRENT_TIMESTAMP;
    $$
);

-- 2. Daily job at 03:00 AM UTC to purge expired OTP challenges (> 24h old)
SELECT cron.schedule(
    'cleanup-expired-otp-challenges',
    '0 3 * * *',
    $$
        DELETE FROM otp_challenges
        WHERE expires_at < CURRENT_TIMESTAMP - INTERVAL '1 day';

        DELETE FROM otp_verification_sessions
        WHERE expires_at < CURRENT_TIMESTAMP - INTERVAL '1 day';
    $$
);

-- 3. Daily job to purge expired rate limit buckets (> 7 days old)
SELECT cron.schedule(
    'cleanup-expired-rate-limits',
    '15 3 * * *',
    $$
        DELETE FROM abuse_rate_limits
        WHERE window_start < CURRENT_TIMESTAMP - INTERVAL '7 days';
    $$
);
