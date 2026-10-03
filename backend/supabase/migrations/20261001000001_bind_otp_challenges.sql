-- ============================================================================
-- Migration: 20261001000001_bind_otp_challenges.sql
-- Description: Bind OTP challenges cryptographically and relationally to mobile and role
-- ============================================================================

ALTER TABLE public.otp_challenges ADD COLUMN IF NOT EXISTS mobile VARCHAR(32);
ALTER TABLE public.otp_challenges ADD COLUMN IF NOT EXISTS role VARCHAR(32);

CREATE INDEX IF NOT EXISTS idx_otp_challenges_mobile_role ON public.otp_challenges(mobile, role);
