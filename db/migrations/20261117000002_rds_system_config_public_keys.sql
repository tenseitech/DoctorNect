-- RDS / replay: remove demo reviewer credentials from DB; keep only public config keys apps expect.
-- Does not edit 20260923000001; idempotent on partially-applied production (demo_accounts row only).
-- doctornect_admin migrator: FORCE RLS + no migrator policy blocks direct DML; brief NO FORCE (same pattern as rds_overrides/20261026000001).

ALTER TABLE public.system_config NO FORCE ROW LEVEL SECURITY;

DELETE FROM public.system_config WHERE config_key = 'demo_accounts';

INSERT INTO public.system_config (config_key, config_value, updated_at)
VALUES (
    'patient_module_status',
    '{"status": "active", "allow_writes": true, "message": "Normal operational state"}'::jsonb,
    CURRENT_TIMESTAMP
)
ON CONFLICT (config_key) DO NOTHING;

INSERT INTO public.system_config (config_key, config_value, updated_at)
VALUES (
    'promoted_ads',
    '{"enabled": true, "pricingTiers": {"24": 300, "72": 750, "168": 1500, "720": 5000}}'::jsonb,
    CURRENT_TIMESTAMP
)
ON CONFLICT (config_key) DO NOTHING;

ALTER TABLE public.system_config FORCE ROW LEVEL SECURITY;