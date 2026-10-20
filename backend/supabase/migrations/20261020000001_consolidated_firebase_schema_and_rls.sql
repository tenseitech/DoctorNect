-- ============================================================================
-- DOCTORNECT PLATFORM — CONSOLIDATED PRODUCTION DDL & ROW-LEVEL SECURITY
-- ============================================================================
-- Migration: 20261020000001_consolidated_firebase_schema_and_rls.sql
--
-- TARGET ARCHITECTURE (Final & Non-Negotiable):
--   - Authentication: Firebase Auth ONLY (JWT tokens bearer verified by Supabase)
--   - Database: Supabase PostgreSQL ONLY (zero dependencies on Supabase auth.users)
--   - Primary Key & Identity: public.users.id is TEXT (Firebase UID)
--   - Foreign Keys: All user-referencing columns are TEXT REFERENCES public.users(id)
--   - RLS Policy Rule: Pure JWT claims via (auth.jwt() ->> 'sub') and (auth.jwt() ->> 'user_role')
--   - Storage: AWS S3 (private bucket, presigned URLs for medical files & reports)
--   - Redis: Ephemeral memory only (OTP mirror, rate limits, URL cache)
--
-- SUPERSEDED MIGRATIONS (22 files consolidated):
--   1.  20260923000001_doctornect_schema.sql (Initial schema - dropped auth.users FK, users.id UUID->TEXT)
--   2.  20260923000002_doctornect_rls.sql (Initial RLS - auth.uid() replaced by auth.jwt()->>'sub')
--   3.  20260923000003_doctornect_cron.sql (Scheduled maintenance jobs)
--   4.  20260925000001_sync_bridge_infra.sql (Dual-write sync bridge tables)
--   5.  20260926000001_atomic_appointment_booking.sql (Atomic booking functions)
--   6.  20260928000001_add_health_records_s3_storage_fields.sql (Inlined S3 storage columns)
--   7.  20260928000002_add_lab_reports_s3_storage_fields.sql (Inlined S3 report columns)
--   8.  20260928000003_add_profile_photos_s3_storage_fields.sql (Inlined S3 photo columns)
--   9.  20260929000001_add_promoted_ads_s3_storage_fields.sql (Inlined S3 ad image columns)
--   10. 20260930000001_fix_security_advisor_warnings.sql (Locked down function search paths)
--   11. 20260930000002_admin_users_table.sql (Decoupled admin table from auth.users)
--   12. 20260930000003_users_integrity.sql (Inlined constraints on users table)
--   13. 20260930000004_access_gap_fixes.sql (Inlined policy fixes)
--   14. 20260930000005_users_provisioning.sql (Inlined user provisioning triggers)
--   15. 20260930000006_column_locks.sql (Inlined column locking triggers)
--   16. 20260930000007_auth_user_lookup.sql (Firebase-aware user lookup)
--   17. 20261001000001_bind_otp_challenges.sql (Inlined challenge binding)
--   18. 20261001000002_harden_auth_provisioning.sql (Inlined provisioning hardening)
--   19. 20261002000001_is_super_admin_null_safe.sql (Null-safe admin functions)
--   20. 20261008000001_firebase_uid_identity.sql (Superseded: users.id is now natively TEXT Firebase UID)
--   21. 20261008000002_super_admin_from_admin_users.sql (Integrated claim-based admin checks)
--   22. 20261008000003_allow_firebase_users_drop_fkey.sql (Dropped auth.users foreign key)
-- ============================================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Schemas
CREATE SCHEMA IF NOT EXISTS private;

-- ============================================================================
-- MIGRATION CHAIN RECONCILIATION: UUID -> TEXT (FIREBASE UID)
-- ============================================================================
-- Converts users.id and all referencing foreign key columns from UUID to TEXT
-- so that migrations applied sequentially from 20260923000001 work seamlessly.

DO $$
DECLARE
    r RECORD;
BEGIN
    -- Drop old function signatures that had RETURNS UUID
    DROP FUNCTION IF EXISTS private.current_user_id() CASCADE;
    DROP FUNCTION IF EXISTS private.current_firebase_uid() CASCADE;
    DROP FUNCTION IF EXISTS private.current_user_role() CASCADE;
    DROP FUNCTION IF EXISTS private.current_profile_id() CASCADE;
    DROP FUNCTION IF EXISTS private.is_super_admin() CASCADE;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'id' AND data_type = 'uuid'
    ) THEN
        -- Dynamically drop all foreign key constraints referencing public.users(id)
        FOR r IN (
            SELECT tc.table_schema, tc.table_name, tc.constraint_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
            WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_schema = 'public' AND ccu.table_name = 'users' AND ccu.column_name = 'id'
        ) LOOP
            EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I', r.table_schema, r.table_name, r.constraint_name);
        END LOOP;

        -- Also drop any self/admin references
        ALTER TABLE IF EXISTS private.admin_users DROP CONSTRAINT IF EXISTS admin_users_user_id_fkey;
        ALTER TABLE IF EXISTS private.admin_users DROP CONSTRAINT IF EXISTS admin_users_granted_by_fkey;

        -- Alter column types from UUID to TEXT
        ALTER TABLE public.users ALTER COLUMN id TYPE TEXT USING id::TEXT;
        ALTER TABLE public.users ALTER COLUMN firebase_uid TYPE TEXT USING firebase_uid::TEXT;
        ALTER TABLE IF EXISTS public.doctors ALTER COLUMN owner_uid TYPE TEXT USING owner_uid::TEXT;
        ALTER TABLE IF EXISTS public.patients ALTER COLUMN owner_uid TYPE TEXT USING owner_uid::TEXT;
        ALTER TABLE IF EXISTS public.medical_stores ALTER COLUMN owner_uid TYPE TEXT USING owner_uid::TEXT;
        ALTER TABLE IF EXISTS public.labs ALTER COLUMN owner_uid TYPE TEXT USING owner_uid::TEXT;
        ALTER TABLE IF EXISTS public.ambulances ALTER COLUMN auth_uid TYPE TEXT USING auth_uid::TEXT;
        ALTER TABLE IF EXISTS public.in_app_notifications ALTER COLUMN recipient_uid TYPE TEXT USING recipient_uid::TEXT;
        ALTER TABLE IF EXISTS public.admin_audit_logs ALTER COLUMN admin_uid TYPE TEXT USING admin_uid::TEXT;
        ALTER TABLE IF EXISTS public.security_events ALTER COLUMN uid TYPE TEXT USING uid::TEXT;
        ALTER TABLE IF EXISTS public.appointments ADD COLUMN IF NOT EXISTS booked_by_uid TEXT REFERENCES public.users(id) ON DELETE SET NULL;
        ALTER TABLE IF EXISTS public.doctors ADD COLUMN IF NOT EXISTS photo_s3_key TEXT;
        ALTER TABLE IF EXISTS public.doctors ADD COLUMN IF NOT EXISTS photo_s3_bucket TEXT;
        ALTER TABLE IF EXISTS public.doctors ADD COLUMN IF NOT EXISTS photo_storage_provider VARCHAR(32) DEFAULT 's3';
        ALTER TABLE IF EXISTS public.patients ADD COLUMN IF NOT EXISTS photo_s3_key TEXT;
        ALTER TABLE IF EXISTS public.patients ADD COLUMN IF NOT EXISTS photo_s3_bucket TEXT;
        ALTER TABLE IF EXISTS public.patients ADD COLUMN IF NOT EXISTS photo_storage_provider VARCHAR(32) DEFAULT 's3';
        ALTER TABLE IF EXISTS public.users ADD COLUMN IF NOT EXISTS photo_s3_key TEXT;
        ALTER TABLE IF EXISTS public.users ADD COLUMN IF NOT EXISTS photo_s3_bucket TEXT;
        ALTER TABLE IF EXISTS public.users ADD COLUMN IF NOT EXISTS photo_storage_provider VARCHAR(32) DEFAULT 's3';
        ALTER TABLE IF EXISTS public.health_records ADD COLUMN IF NOT EXISTS s3_key TEXT;
        ALTER TABLE IF EXISTS public.health_records ADD COLUMN IF NOT EXISTS s3_bucket TEXT;
        ALTER TABLE IF EXISTS private.admin_users ALTER COLUMN user_id TYPE TEXT USING user_id::TEXT;
        ALTER TABLE IF EXISTS private.admin_users ALTER COLUMN granted_by TYPE TEXT USING granted_by::TEXT;

        -- Re-add foreign key constraints pointing to public.users(id)
        ALTER TABLE IF EXISTS public.doctors ADD CONSTRAINT doctors_owner_uid_fkey FOREIGN KEY (owner_uid) REFERENCES public.users(id) ON DELETE SET NULL;
        ALTER TABLE IF EXISTS public.patients ADD CONSTRAINT patients_owner_uid_fkey FOREIGN KEY (owner_uid) REFERENCES public.users(id) ON DELETE SET NULL;
        ALTER TABLE IF EXISTS public.medical_stores ADD CONSTRAINT medical_stores_owner_uid_fkey FOREIGN KEY (owner_uid) REFERENCES public.users(id) ON DELETE SET NULL;
        ALTER TABLE IF EXISTS public.labs ADD CONSTRAINT labs_owner_uid_fkey FOREIGN KEY (owner_uid) REFERENCES public.users(id) ON DELETE SET NULL;
        ALTER TABLE IF EXISTS public.ambulances ADD CONSTRAINT ambulances_auth_uid_fkey FOREIGN KEY (auth_uid) REFERENCES public.users(id) ON DELETE SET NULL;
        ALTER TABLE IF EXISTS public.in_app_notifications ADD CONSTRAINT in_app_notifications_recipient_uid_fkey FOREIGN KEY (recipient_uid) REFERENCES public.users(id) ON DELETE CASCADE;
        ALTER TABLE IF EXISTS public.admin_audit_logs ADD CONSTRAINT admin_audit_logs_admin_uid_fkey FOREIGN KEY (admin_uid) REFERENCES public.users(id) ON DELETE SET NULL;
        ALTER TABLE IF EXISTS public.security_events ADD CONSTRAINT security_events_uid_fkey FOREIGN KEY (uid) REFERENCES public.users(id) ON DELETE SET NULL;
        ALTER TABLE IF EXISTS private.admin_users ADD CONSTRAINT admin_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
        ALTER TABLE IF EXISTS private.admin_users ADD CONSTRAINT admin_users_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.users(id) ON DELETE SET NULL;
    END IF;
END $$;


-- ============================================================================
-- 0. CORE UTILITY TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 1. FACILITIES & CLINICAL LOCATIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS facilities (
    facility_id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    facility_type VARCHAR(32) NOT NULL DEFAULT 'clinic' 
        CHECK (facility_type IN ('clinic', 'hospital', 'nursing_home', 'diagnostic_center', 'daycare')),
    address TEXT,
    city VARCHAR(128) NOT NULL,
    state VARCHAR(128),
    country VARCHAR(64) DEFAULT 'India',
    pincode VARCHAR(16),
    phone VARCHAR(32),
    email VARCHAR(255),
    license_number VARCHAR(128),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_facilities_city ON facilities(city);
CREATE INDEX IF NOT EXISTS idx_facilities_type ON facilities(facility_type);

DROP TRIGGER IF EXISTS set_facilities_timestamp ON facilities;
CREATE TRIGGER set_facilities_timestamp
    BEFORE UPDATE ON facilities
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ============================================================================
-- 2. AUTHENTICATION & CORE USER IDENTITY (PRIMARY KEY = TEXT FIREBASE UID)
-- ============================================================================

CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY, -- Firebase UID (e.g. '0a1b2c3d4e5f...')
    firebase_uid TEXT UNIQUE, -- Kept for backward compatibility (mirrors id)
    role VARCHAR(32) NOT NULL CHECK (role IN (
        'super_admin', 'superAdmin', 'admin',
        'doctor', 'patient', 'medicalStore', 'lab', 'ambulance',
        'nurse', 'receptionist', 'billing_staff', 'hospital_admin'
    )),
    profile_id VARCHAR(64) NOT NULL,
    display_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    mobile VARCHAR(32),
    profile_completed BOOLEAN NOT NULL DEFAULT FALSE,
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMPTZ,
    deactivated BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(32) DEFAULT 'approved',
    photo_url TEXT,
    photo_s3_key TEXT,
    photo_s3_bucket TEXT,
    photo_storage_provider VARCHAR(32) DEFAULT 's3',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_mobile ON users(mobile);
CREATE INDEX IF NOT EXISTS idx_users_profile_id ON users(profile_id);
CREATE INDEX IF NOT EXISTS idx_users_firebase_uid ON users(firebase_uid);

DROP TRIGGER IF EXISTS set_users_timestamp ON users;
CREATE TRIGGER set_users_timestamp
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ============================================================================
-- 3. DEDICATED ADMIN USERS TABLE (PRIVATE SCHEMA)
-- ============================================================================

CREATE TABLE IF NOT EXISTS private.admin_users (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    granted_by TEXT REFERENCES users(id) ON DELETE SET NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

REVOKE ALL ON TABLE private.admin_users FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE private.admin_users TO service_role;

-- ============================================================================
-- 4. HEALTHCARE PROVIDERS: DOCTORS
-- ============================================================================

CREATE TABLE IF NOT EXISTS doctors (
    doctor_id VARCHAR(64) PRIMARY KEY,
    owner_uid TEXT REFERENCES users(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    mobile VARCHAR(32) NOT NULL,
    specialization VARCHAR(128) NOT NULL,
    super_specialization TEXT,
    qualification VARCHAR(255) NOT NULL,
    experience_years INT NOT NULL DEFAULT 1,
    consultation_fee NUMERIC(10, 2) DEFAULT 0.00,
    clinic_name VARCHAR(255),
    primary_facility_id VARCHAR(64) REFERENCES facilities(facility_id) ON DELETE SET NULL,
    area VARCHAR(128),
    city VARCHAR(128),
    state VARCHAR(128),
    country VARCHAR(64) DEFAULT 'India',
    pincode VARCHAR(16),
    address_line1 TEXT,
    address_line2 TEXT,
    state_council VARCHAR(255),
    council_number VARCHAR(128),
    certifications TEXT[] DEFAULT ARRAY[]::TEXT[],
    past_workplaces TEXT[] DEFAULT ARRAY[]::TEXT[],
    memberships TEXT[] DEFAULT ARRAY[]::TEXT[],
    awards TEXT[] DEFAULT ARRAY[]::TEXT[],
    publications TEXT[] DEFAULT ARRAY[]::TEXT[],
    about TEXT,
    languages TEXT[] DEFAULT ARRAY['English', 'Hindi']::TEXT[],
    photo_url TEXT,
    photo_s3_key TEXT,
    photo_s3_bucket TEXT,
    photo_storage_provider VARCHAR(32) DEFAULT 's3',
    maps_link TEXT,
    landmark VARCHAR(255),
    rating NUMERIC(3, 2) NOT NULL DEFAULT 0.00,
    review_count INT NOT NULL DEFAULT 0,
    profile_completed BOOLEAN NOT NULL DEFAULT FALSE,
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMPTZ,
    deactivated BOOLEAN NOT NULL DEFAULT FALSE,
    deactivated_at TIMESTAMPTZ,
    reactivate_before TIMESTAMPTZ,
    reactivated_at TIMESTAMPTZ,
    fcm_token TEXT,
    fcm_token_updated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_doctors_verified_city ON doctors(verified, city);
CREATE INDEX IF NOT EXISTS idx_doctors_specialization ON doctors(specialization);
CREATE INDEX IF NOT EXISTS idx_doctors_owner_uid ON doctors(owner_uid);
CREATE INDEX IF NOT EXISTS idx_doctors_facility ON doctors(primary_facility_id);

DROP TRIGGER IF EXISTS set_doctors_timestamp ON doctors;
CREATE TRIGGER set_doctors_timestamp
    BEFORE UPDATE ON doctors
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS doctor_facilities (
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    facility_id VARCHAR(64) NOT NULL REFERENCES facilities(facility_id) ON DELETE CASCADE,
    department VARCHAR(128),
    consultation_fee NUMERIC(10, 2),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (doctor_id, facility_id)
);

CREATE TABLE IF NOT EXISTS doctor_education (
    id BIGSERIAL PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    degree VARCHAR(128) NOT NULL,
    college VARCHAR(255),
    year INT
);

CREATE TABLE IF NOT EXISTS doctor_availability (
    doctor_id VARCHAR(64) PRIMARY KEY REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    working_days TEXT[] NOT NULL DEFAULT ARRAY['Mon', 'Tue', 'Wed', 'Thu', 'Fri']::TEXT[],
    morning_start VARCHAR(16) NOT NULL DEFAULT '09:00 AM',
    morning_end VARCHAR(16) NOT NULL DEFAULT '01:00 PM',
    evening_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    evening_start VARCHAR(16) NOT NULL DEFAULT '04:00 PM',
    evening_end VARCHAR(16) NOT NULL DEFAULT '08:00 PM',
    slot_duration_mins INT NOT NULL DEFAULT 15,
    max_patients_per_day INT NOT NULL DEFAULT 20,
    break_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    break_start VARCHAR(16) DEFAULT '01:00 PM',
    break_end VARCHAR(16) DEFAULT '02:00 PM',
    leave_start TIMESTAMPTZ,
    leave_end TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS doctor_blocked_dates (
    id BIGSERIAL PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    blocked_date DATE NOT NULL,
    UNIQUE(doctor_id, blocked_date)
);

-- ============================================================================
-- 5. PATIENTS & FAMILY HEALTH PROFILES
-- ============================================================================

CREATE TABLE IF NOT EXISTS patients (
    patient_id VARCHAR(64) PRIMARY KEY,
    owner_uid TEXT REFERENCES users(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    mobile VARCHAR(32) NOT NULL,
    age INT,
    gender VARCHAR(16) CHECK (gender IN ('Male', 'Female', 'Other')),
    blood_group VARCHAR(8),
    height VARCHAR(32),
    weight VARCHAR(32),
    address TEXT,
    photo_url TEXT,
    photo_s3_key TEXT,
    photo_s3_bucket TEXT,
    photo_storage_provider VARCHAR(32) DEFAULT 's3',
    share_records_with_doctors BOOLEAN NOT NULL DEFAULT TRUE,
    primary_doctor_id VARCHAR(64) REFERENCES doctors(doctor_id) ON DELETE SET NULL,
    invited_doctor_id VARCHAR(64) REFERENCES doctors(doctor_id) ON DELETE SET NULL,
    care_team_doctor_ids TEXT[] DEFAULT ARRAY[]::TEXT[],
    profile_completed BOOLEAN NOT NULL DEFAULT TRUE,
    verified BOOLEAN NOT NULL DEFAULT TRUE,
    fcm_token TEXT,
    fcm_token_updated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_patients_owner_uid ON patients(owner_uid);
CREATE INDEX IF NOT EXISTS idx_patients_mobile ON patients(mobile);

DROP TRIGGER IF EXISTS set_patients_timestamp ON patients;
CREATE TRIGGER set_patients_timestamp
    BEFORE UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS patient_care_team (
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (patient_id, doctor_id)
);

CREATE TABLE IF NOT EXISTS patient_doctor_links (
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    source VARCHAR(32) NOT NULL CHECK (source IN ('appointment', 'referral', 'manual')),
    from_doctor_id VARCHAR(64) REFERENCES doctors(doctor_id) ON DELETE SET NULL,
    referral_id VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (patient_id, doctor_id)
);

CREATE TABLE IF NOT EXISTS family_members (
    member_id VARCHAR(64) PRIMARY KEY,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    relation VARCHAR(32) NOT NULL CHECK (relation IN ('spouse', 'child', 'parent', 'sibling', 'grandparent', 'other')),
    age INT NOT NULL,
    gender VARCHAR(16) NOT NULL,
    blood_group VARCHAR(8),
    insurance_covered BOOLEAN NOT NULL DEFAULT FALSE,
    date_of_birth DATE,
    photo_initial VARCHAR(8),
    allergies TEXT[] DEFAULT ARRAY[]::TEXT[],
    conditions TEXT[] DEFAULT ARRAY[]::TEXT[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_family_members_patient ON family_members(patient_id);

DROP TRIGGER IF EXISTS set_family_members_timestamp ON family_members;
CREATE TRIGGER set_family_members_timestamp
    BEFORE UPDATE ON family_members
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ============================================================================
-- 6. MEDICAL STORES / PHARMACIES
-- ============================================================================

CREATE TABLE IF NOT EXISTS medical_stores (
    store_id VARCHAR(64) PRIMARY KEY,
    owner_uid TEXT REFERENCES users(id) ON DELETE SET NULL,
    store_name VARCHAR(255) NOT NULL,
    owner_name VARCHAR(255) NOT NULL,
    drug_license_number VARCHAR(128) NOT NULL,
    phone VARCHAR(32) NOT NULL,
    email VARCHAR(255) NOT NULL,
    gst_number VARCHAR(64),
    address_line1 TEXT,
    address_line2 TEXT,
    city VARCHAR(128),
    state VARCHAR(128),
    country VARCHAR(64) DEFAULT 'India',
    pincode VARCHAR(16),
    profile_completed BOOLEAN NOT NULL DEFAULT FALSE,
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMPTZ,
    deactivated BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_medical_stores_verified_city ON medical_stores(verified, city);
CREATE INDEX IF NOT EXISTS idx_medical_stores_owner ON medical_stores(owner_uid);

DROP TRIGGER IF EXISTS set_medical_stores_timestamp ON medical_stores;
CREATE TRIGGER set_medical_stores_timestamp
    BEFORE UPDATE ON medical_stores
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ============================================================================
-- 7. DIAGNOSTIC LABORATORIES
-- ============================================================================

CREATE TABLE IF NOT EXISTS labs (
    lab_id VARCHAR(64) PRIMARY KEY,
    owner_uid TEXT REFERENCES users(id) ON DELETE SET NULL,
    lab_name VARCHAR(255) NOT NULL,
    license_number VARCHAR(128) NOT NULL,
    phone VARCHAR(32) NOT NULL,
    email VARCHAR(255) NOT NULL,
    gst_number VARCHAR(64),
    rating NUMERIC(3, 2) NOT NULL DEFAULT 0.00,
    area VARCHAR(128),
    city VARCHAR(128),
    state VARCHAR(128),
    country VARCHAR(64) DEFAULT 'India',
    pincode VARCHAR(16),
    address_line1 TEXT,
    address_line2 TEXT,
    profile_completed BOOLEAN NOT NULL DEFAULT FALSE,
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMPTZ,
    deactivated BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_labs_verified_city ON labs(verified, city);
CREATE INDEX IF NOT EXISTS idx_labs_owner ON labs(owner_uid);

DROP TRIGGER IF EXISTS set_labs_timestamp ON labs;
CREATE TRIGGER set_labs_timestamp
    BEFORE UPDATE ON labs
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS lab_catalog_tests (
    test_id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    parameters TEXT[] DEFAULT ARRAY[]::TEXT[],
    fasting_required BOOLEAN NOT NULL DEFAULT FALSE,
    sample_type VARCHAR(32) NOT NULL DEFAULT 'blood' CHECK (sample_type IN ('blood', 'urine', 'swab', 'stool', 'other')),
    report_hours INT NOT NULL DEFAULT 24,
    popular BOOLEAN NOT NULL DEFAULT FALSE,
    category VARCHAR(128)
);

CREATE INDEX IF NOT EXISTS idx_lab_catalog_category ON lab_catalog_tests(category);

-- ============================================================================
-- 8. AMBULANCE SERVICES & DRIVERS
-- ============================================================================

CREATE TABLE IF NOT EXISTS ambulances (
    ambulance_id VARCHAR(64) PRIMARY KEY,
    auth_uid TEXT REFERENCES users(id) ON DELETE SET NULL,
    service_name VARCHAR(255) NOT NULL,
    owner_name VARCHAR(255),
    driver_name VARCHAR(255) NOT NULL,
    phone VARCHAR(32) NOT NULL,
    vehicle_number VARCHAR(64) NOT NULL,
    ambulance_type VARCHAR(32) NOT NULL CHECK (ambulance_type IN ('bls', 'als', 'icu', 'patientTransport')),
    username VARCHAR(64) UNIQUE,
    city VARCHAR(128) NOT NULL,
    base_address TEXT,
    license_number VARCHAR(128),
    insurance_number VARCHAR(128),
    has_oxygen BOOLEAN NOT NULL DEFAULT FALSE,
    has_ventilator BOOLEAN NOT NULL DEFAULT FALSE,
    has_stretcher BOOLEAN NOT NULL DEFAULT TRUE,
    is_24x7 BOOLEAN NOT NULL DEFAULT FALSE,
    rate_per_km NUMERIC(10, 2),
    total_rating NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    rating_count INT NOT NULL DEFAULT 0,
    is_available BOOLEAN NOT NULL DEFAULT TRUE,
    profile_completed BOOLEAN NOT NULL DEFAULT FALSE,
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    address_line1 TEXT,
    address_line2 TEXT,
    state VARCHAR(128),
    country VARCHAR(64) DEFAULT 'India',
    pincode VARCHAR(16),
    service_areas TEXT[] DEFAULT ARRAY[]::TEXT[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ambulances_city_available ON ambulances(city, is_available);
CREATE INDEX IF NOT EXISTS idx_ambulances_auth_uid ON ambulances(auth_uid);

DROP TRIGGER IF EXISTS set_ambulances_timestamp ON ambulances;
CREATE TRIGGER set_ambulances_timestamp
    BEFORE UPDATE ON ambulances
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS ambulance_private_settings (
    ambulance_id VARCHAR(64) PRIMARY KEY REFERENCES ambulances(ambulance_id) ON DELETE CASCADE,
    pin_hash VARCHAR(255) NOT NULL,
    fcm_token TEXT,
    fcm_token_updated_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 9. APPOINTMENTS (OPD & IPD Extended)
-- ============================================================================

CREATE TABLE IF NOT EXISTS appointments (
    appointment_id VARCHAR(64) PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE RESTRICT,
    facility_id VARCHAR(64) REFERENCES facilities(facility_id) ON DELETE SET NULL,
    encounter_type VARCHAR(32) NOT NULL DEFAULT 'opd' 
        CHECK (encounter_type IN ('opd', 'ipd', 'emergency', 'teleconsult')),
    admission_id VARCHAR(64),
    doctor_name VARCHAR(255) NOT NULL,
    specialization VARCHAR(128) NOT NULL,
    patient_name VARCHAR(255) NOT NULL,
    patient_age INT NOT NULL,
    patient_gender VARCHAR(16) NOT NULL,
    date_time TIMESTAMPTZ NOT NULL,
    slot_label VARCHAR(32) NOT NULL,
    token_number INT NOT NULL DEFAULT 0,
    visit_type VARCHAR(32) NOT NULL CHECK (visit_type IN ('newVisit', 'followUp', 'returning')),
    patient_status VARCHAR(32) NOT NULL CHECK (patient_status IN ('pending', 'confirmed', 'completed', 'cancelled')),
    doctor_status VARCHAR(32) NOT NULL CHECK (doctor_status IN ('pendingRequest', 'confirmed', 'inProgress', 'completed', 'cancelled', 'noShow', 'waiting')),
    clinic_name VARCHAR(255),
    clinic_address TEXT,
    maps_url TEXT,
    cancellation_reason TEXT,
    diagnosis TEXT,
    has_prescription BOOLEAN NOT NULL DEFAULT FALSE,
    has_report BOOLEAN NOT NULL DEFAULT FALSE,
    has_review BOOLEAN NOT NULL DEFAULT FALSE,
    review_rating INT CHECK (review_rating BETWEEN 1 AND 5),
    review_id VARCHAR(128),
    review_created_at TIMESTAMPTZ,
    clinical_notes TEXT,
    contact_number VARCHAR(32),
    source VARCHAR(32) DEFAULT 'app' CHECK (source IN ('app', 'walkin', 'referral')),
    booked_by_name VARCHAR(255),
    patient_relation VARCHAR(64),
    slot_share_reason VARCHAR(128),
    was_rescheduled BOOLEAN NOT NULL DEFAULT FALSE,
    chief_complaints TEXT[] DEFAULT ARRAY[]::TEXT[],
    symptoms TEXT[] DEFAULT ARRAY[]::TEXT[],
    observations TEXT[] DEFAULT ARRAY[]::TEXT[],
    lab_reports TEXT[] DEFAULT ARRAY[]::TEXT[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_appointments_doctor_date ON appointments(doctor_id, date_time);
CREATE INDEX IF NOT EXISTS idx_appointments_patient_date ON appointments(patient_id, date_time);
CREATE INDEX IF NOT EXISTS idx_appointments_doctor_status ON appointments(doctor_id, doctor_status);

DROP TRIGGER IF EXISTS set_appointments_timestamp ON appointments;
CREATE TRIGGER set_appointments_timestamp
    BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ============================================================================
-- 10. PRESCRIPTIONS & CLINICAL REGIMENS
-- ============================================================================

CREATE TABLE IF NOT EXISTS prescriptions (
    prescription_id VARCHAR(64) PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE RESTRICT,
    appointment_id VARCHAR(64) REFERENCES appointments(appointment_id) ON DELETE SET NULL,
    facility_id VARCHAR(64) REFERENCES facilities(facility_id) ON DELETE SET NULL,
    encounter_type VARCHAR(32) NOT NULL DEFAULT 'opd' CHECK (encounter_type IN ('opd', 'ipd', 'emergency')),
    admission_id VARCHAR(64),
    doctor_name VARCHAR(255),
    doctor_specialization VARCHAR(128),
    doctor_qualifications VARCHAR(255),
    doctor_reg_number VARCHAR(128),
    clinic_name VARCHAR(255),
    clinic_address TEXT,
    doctor_phone VARCHAR(32),
    patient_name VARCHAR(255) NOT NULL,
    patient_age INT NOT NULL,
    patient_gender VARCHAR(16),
    prescription_date TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    diagnosis_type VARCHAR(32) DEFAULT 'Provisional' CHECK (diagnosis_type IN ('Provisional', 'Final')),
    primary_diagnosis TEXT,
    secondary_diagnosis TEXT,
    chief_complaint TEXT,
    symptoms TEXT,
    symptom_duration VARCHAR(64),
    past_history TEXT,
    allergies TEXT,
    general_examination TEXT,
    blood_pressure VARCHAR(32),
    temperature VARCHAR(32),
    pulse VARCHAR(32),
    spo2 VARCHAR(32),
    weight_kg VARCHAR(32),
    height_cm VARCHAR(32),
    respiratory_rate VARCHAR(32),
    diet_advice TEXT,
    activity_restrictions TEXT,
    lifestyle_advice TEXT,
    general_advice TEXT,
    follow_up_note TEXT,
    next_visit TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_prescriptions_patient ON prescriptions(patient_id, prescription_date DESC);
CREATE INDEX IF NOT EXISTS idx_prescriptions_doctor ON prescriptions(doctor_id, prescription_date DESC);

DROP TRIGGER IF EXISTS set_prescriptions_timestamp ON prescriptions;
CREATE TRIGGER set_prescriptions_timestamp
    BEFORE UPDATE ON prescriptions
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS prescription_medicines (
    id BIGSERIAL PRIMARY KEY,
    prescription_id VARCHAR(64) NOT NULL REFERENCES prescriptions(prescription_id) ON DELETE CASCADE,
    medicine_entry_id VARCHAR(64) NOT NULL,
    name VARCHAR(255) NOT NULL,
    dosage VARCHAR(64) NOT NULL,
    form VARCHAR(64) NOT NULL,
    frequency VARCHAR(64) NOT NULL,
    quantity VARCHAR(32) NOT NULL,
    duration VARCHAR(64) NOT NULL,
    instructions TEXT,
    special_instructions TEXT,
    is_sos BOOLEAN NOT NULL DEFAULT FALSE,
    substitute_allowed BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS prescription_investigations (
    id BIGSERIAL PRIMARY KEY,
    prescription_id VARCHAR(64) NOT NULL REFERENCES prescriptions(prescription_id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(32) NOT NULL CHECK (type IN ('lab', 'radiology', 'custom')),
    group_name VARCHAR(128),
    notes TEXT
);

CREATE TABLE IF NOT EXISTS prescription_referrals (
    id BIGSERIAL PRIMARY KEY,
    prescription_id VARCHAR(64) NOT NULL REFERENCES prescriptions(prescription_id) ON DELETE CASCADE,
    to_doctor_id VARCHAR(64) REFERENCES doctors(doctor_id) ON DELETE SET NULL,
    doctor_name VARCHAR(255) NOT NULL,
    specialization VARCHAR(128) NOT NULL,
    reason TEXT,
    sent BOOLEAN NOT NULL DEFAULT FALSE
);

-- ============================================================================
-- 11. PATIENT HEALTH RECORDS (CLINICAL VAULT & AWS S3 INTEGRATION)
-- ============================================================================

CREATE TABLE IF NOT EXISTS health_records (
    record_id VARCHAR(64) PRIMARY KEY,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    facility_id VARCHAR(64) REFERENCES facilities(facility_id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    type VARCHAR(32) NOT NULL CHECK (type IN ('prescription', 'labReport', 'dischargeSummary', 'vaccination', 'invoice', 'other')),
    date TIMESTAMPTZ NOT NULL,
    source VARCHAR(32) NOT NULL CHECK (source IN ('selfUploaded', 'doctorPrescribed', 'labGenerated')),
    file_name VARCHAR(255) NOT NULL,
    doctor_name VARCHAR(255),
    lab_name VARCHAR(255),
    is_image BOOLEAN NOT NULL DEFAULT FALSE,
    notes TEXT,
    shared_with_doctors BOOLEAN NOT NULL DEFAULT FALSE,
    file_storage VARCHAR(32) NOT NULL DEFAULT 'cloudUploaded' CHECK (file_storage IN ('none', 'localOnly', 'cloudUploaded')),
    storage_url TEXT,
    s3_key TEXT,
    s3_bucket TEXT,
    storage_provider VARCHAR(32) DEFAULT 's3',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_health_records_patient ON health_records(patient_id, date DESC);

DROP TRIGGER IF EXISTS set_health_records_timestamp ON health_records;
CREATE TRIGGER set_health_records_timestamp
    BEFORE UPDATE ON health_records
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ============================================================================
-- 12. DIAGNOSTIC LAB BOOKINGS & LAB ORDERS (WITH AWS S3 STORAGE)
-- ============================================================================

CREATE TABLE IF NOT EXISTS lab_bookings (
    booking_id VARCHAR(64) PRIMARY KEY,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE RESTRICT,
    lab_id VARCHAR(64) REFERENCES labs(lab_id) ON DELETE SET NULL,
    patient_name VARCHAR(255) NOT NULL,
    patient_age INT NOT NULL,
    patient_gender VARCHAR(16),
    contact_number VARCHAR(32),
    test_id VARCHAR(128) NOT NULL,
    test_name TEXT NOT NULL,
    test_names TEXT[] NOT NULL,
    test_ids TEXT[] DEFAULT ARRAY[]::TEXT[],
    booking_for_self BOOLEAN NOT NULL DEFAULT TRUE,
    family_member_id VARCHAR(64) REFERENCES family_members(member_id) ON DELETE SET NULL,
    collection_type VARCHAR(32) NOT NULL CHECK (collection_type IN ('homeCollection', 'labVisit', 'walkIn')),
    partner_lab VARCHAR(255),
    address TEXT,
    date_time TIMESTAMPTZ NOT NULL,
    slot_label VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL CHECK (status IN ('confirmed', 'sampleCollected', 'inAnalysis', 'completed', 'cancelled')),
    source VARCHAR(32) DEFAULT 'app' CHECK (source IN ('app', 'walkin')),
    report_file_name VARCHAR(255),
    report_storage_url TEXT,
    report_s3_key TEXT,
    report_s3_bucket TEXT,
    report_storage_provider VARCHAR(32) DEFAULT 's3',
    report_booking_id VARCHAR(64),
    report_submitted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_lab_bookings_patient ON lab_bookings(patient_id, date_time DESC);
CREATE INDEX IF NOT EXISTS idx_lab_bookings_lab ON lab_bookings(lab_id, date_time DESC);

DROP TRIGGER IF EXISTS set_lab_bookings_timestamp ON lab_bookings;
CREATE TRIGGER set_lab_bookings_timestamp
    BEFORE UPDATE ON lab_bookings
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS lab_orders (
    order_id VARCHAR(64) PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE RESTRICT,
    lab_id VARCHAR(64) REFERENCES labs(lab_id) ON DELETE SET NULL,
    appointment_id VARCHAR(64) REFERENCES appointments(appointment_id) ON DELETE SET NULL,
    facility_id VARCHAR(64) REFERENCES facilities(facility_id) ON DELETE SET NULL,
    admission_id VARCHAR(64),
    doctor_name VARCHAR(255) NOT NULL,
    patient_name VARCHAR(255) NOT NULL,
    patient_age INT NOT NULL,
    lab_name VARCHAR(255),
    test_ids TEXT[] NOT NULL,
    test_names TEXT[] NOT NULL,
    indication TEXT,
    urgency VARCHAR(32) NOT NULL DEFAULT 'Routine' CHECK (urgency IN ('Routine', 'Urgent', 'STAT')),
    fasting_required BOOLEAN NOT NULL DEFAULT FALSE,
    home_collection BOOLEAN NOT NULL DEFAULT FALSE,
    source VARCHAR(32) NOT NULL DEFAULT 'investigations',
    status VARCHAR(32) NOT NULL DEFAULT 'ordered' CHECK (status IN ('ordered', 'received', 'inProgress', 'completed', 'cancelled')),
    report_file_name VARCHAR(255),
    report_storage_url TEXT,
    report_s3_key TEXT,
    report_s3_bucket TEXT,
    report_storage_provider VARCHAR(32) DEFAULT 's3',
    report_submitted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_lab_orders_doctor ON lab_orders(doctor_id);
CREATE INDEX IF NOT EXISTS idx_lab_orders_patient ON lab_orders(patient_id);
CREATE INDEX IF NOT EXISTS idx_lab_orders_lab ON lab_orders(lab_id);

DROP TRIGGER IF EXISTS set_lab_orders_timestamp ON lab_orders;
CREATE TRIGGER set_lab_orders_timestamp
    BEFORE UPDATE ON lab_orders
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ============================================================================
-- 13. B2B NETWORK CONNECTIONS & PHARMACY DISPENSE
-- ============================================================================

CREATE TABLE IF NOT EXISTS pharmacy_connections (
    connection_id VARCHAR(64) PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    medical_store_id VARCHAR(64) NOT NULL REFERENCES medical_stores(store_id) ON DELETE CASCADE,
    doctor_name VARCHAR(255) NOT NULL,
    store_name VARCHAR(255) NOT NULL,
    status VARCHAR(32) NOT NULL CHECK (status IN ('pending', 'active', 'rejected', 'removed')),
    requested_by VARCHAR(32) NOT NULL CHECK (requested_by IN ('doctor', 'store')),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(doctor_id, medical_store_id)
);

CREATE TABLE IF NOT EXISTS lab_connections (
    connection_id VARCHAR(64) PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    lab_id VARCHAR(64) NOT NULL REFERENCES labs(lab_id) ON DELETE CASCADE,
    doctor_name VARCHAR(255) NOT NULL,
    lab_name VARCHAR(255) NOT NULL,
    status VARCHAR(32) NOT NULL CHECK (status IN ('pending', 'active', 'rejected', 'removed')),
    requested_by VARCHAR(32) NOT NULL CHECK (requested_by IN ('doctor', 'lab')),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(doctor_id, lab_id)
);

CREATE TABLE IF NOT EXISTS pharmacy_deliveries (
    delivery_id VARCHAR(64) PRIMARY KEY,
    prescription_id VARCHAR(64) NOT NULL REFERENCES prescriptions(prescription_id) ON DELETE RESTRICT,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    store_id VARCHAR(64) NOT NULL REFERENCES medical_stores(store_id) ON DELETE RESTRICT,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE RESTRICT,
    doctor_name VARCHAR(255) NOT NULL,
    store_name VARCHAR(255) NOT NULL,
    patient_name VARCHAR(255) NOT NULL,
    status VARCHAR(32) NOT NULL CHECK (status IN ('sent', 'viewed', 'partiallyDispensed', 'dispensed')),
    sent_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    viewed_at TIMESTAMPTZ,
    dispensed_at TIMESTAMPTZ,
    dispensing_notes TEXT,
    medicine_count INT NOT NULL DEFAULT 0,
    prescription_draft JSONB,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_pharmacy_deliv_store ON pharmacy_deliveries(store_id, status);
CREATE INDEX IF NOT EXISTS idx_pharmacy_deliv_patient ON pharmacy_deliveries(patient_id);
CREATE INDEX IF NOT EXISTS idx_pharmacy_deliv_presc ON pharmacy_deliveries(prescription_id);

DROP TRIGGER IF EXISTS set_pharmacy_deliveries_timestamp ON pharmacy_deliveries;
CREATE TRIGGER set_pharmacy_deliveries_timestamp
    BEFORE UPDATE ON pharmacy_deliveries
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS pharmacy_delivery_medicines (
    id BIGSERIAL PRIMARY KEY,
    delivery_id VARCHAR(64) NOT NULL REFERENCES pharmacy_deliveries(delivery_id) ON DELETE CASCADE,
    medicine_entry_id VARCHAR(64) NOT NULL,
    availability VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (availability IN ('pending', 'available', 'outOfStock', 'substituted')),
    substitute_name VARCHAR(255)
);

-- ============================================================================
-- 14. REFERRALS & MEDICAL DIRECTORY
-- ============================================================================

CREATE TABLE IF NOT EXISTS referrals (
    referral_id VARCHAR(64) PRIMARY KEY,
    from_doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    to_doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE RESTRICT,
    appointment_id VARCHAR(64) REFERENCES appointments(appointment_id) ON DELETE SET NULL,
    from_doctor_name VARCHAR(255) NOT NULL,
    to_doctor_name VARCHAR(255) NOT NULL,
    to_specialization VARCHAR(128) NOT NULL,
    patient_name VARCHAR(255) NOT NULL,
    patient_age INT NOT NULL,
    reason TEXT,
    status VARCHAR(32) NOT NULL DEFAULT 'sent' CHECK (status IN ('sent', 'accepted', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS medical_directory (
    entry_id VARCHAR(64) PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(64) NOT NULL,
    phone VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ
);

-- ============================================================================
-- 15. REVIEWS & PUBLIC PROJECTIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS reviews (
    review_id VARCHAR(128) PRIMARY KEY,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    appointment_id VARCHAR(64) REFERENCES appointments(appointment_id) ON DELETE SET NULL,
    patient_name VARCHAR(255) NOT NULL,
    rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT NOT NULL,
    doctor_reply TEXT,
    helpful_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(patient_id, doctor_id)
);

DROP TRIGGER IF EXISTS set_reviews_timestamp ON reviews;
CREATE TRIGGER set_reviews_timestamp
    BEFORE UPDATE ON reviews
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS review_public (
    review_id VARCHAR(128) PRIMARY KEY REFERENCES reviews(review_id) ON DELETE CASCADE,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT NOT NULL,
    masked_name VARCHAR(64) NOT NULL,
    helpful_count INT NOT NULL DEFAULT 0,
    doctor_reply TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS review_votes (
    review_id VARCHAR(128) NOT NULL REFERENCES reviews(review_id) ON DELETE CASCADE,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (review_id, patient_id)
);

-- ============================================================================
-- 16. CUSTOMER SUPPORT & TICKETING
-- ============================================================================

CREATE TABLE IF NOT EXISTS support_tickets (
    ticket_id VARCHAR(64) PRIMARY KEY,
    patient_id VARCHAR(64) REFERENCES patients(patient_id) ON DELETE SET NULL,
    doctor_id VARCHAR(64) REFERENCES doctors(doctor_id) ON DELETE SET NULL,
    issue_type VARCHAR(64) NOT NULL CHECK (issue_type IN ('Appointment', 'Records', 'Technical', 'Other')),
    message TEXT NOT NULL,
    screenshot_name VARCHAR(255),
    status VARCHAR(32) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DROP TRIGGER IF EXISTS set_support_tickets_timestamp ON support_tickets;
CREATE TRIGGER set_support_tickets_timestamp
    BEFORE UPDATE ON support_tickets
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS support_ticket_messages (
    message_id VARCHAR(64) PRIMARY KEY,
    ticket_id VARCHAR(64) NOT NULL REFERENCES support_tickets(ticket_id) ON DELETE CASCADE,
    sender_id VARCHAR(128) NOT NULL,
    sender_name VARCHAR(255) NOT NULL,
    sender_role VARCHAR(32) NOT NULL CHECK (sender_role IN ('patient', 'doctor', 'support')),
    text TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 17. AMBULANCE DISPATCH & EMERGENCY BROADCASTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS ambulance_broadcasts (
    broadcast_id VARCHAR(64) PRIMARY KEY,
    patient_id VARCHAR(64) NOT NULL,
    patient_name VARCHAR(255) NOT NULL,
    pickup_location TEXT NOT NULL,
    drop_location TEXT NOT NULL,
    contact_phone VARCHAR(32) NOT NULL,
    notes TEXT,
    status VARCHAR(32) NOT NULL CHECK (status IN ('pending', 'accepted', 'completed', 'cancelled')),
    accepted_driver_id VARCHAR(64) REFERENCES ambulances(ambulance_id) ON DELETE SET NULL,
    accepted_driver_name VARCHAR(255),
    accepted_driver_phone VARCHAR(32),
    accepted_vehicle_number VARCHAR(64),
    accepted_ambulance_type VARCHAR(64),
    accepted_at TIMESTAMPTZ,
    rating INT,
    review TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_amb_broadcasts_status ON ambulance_broadcasts(status);

DROP TRIGGER IF EXISTS set_ambulance_broadcasts_timestamp ON ambulance_broadcasts;
CREATE TRIGGER set_ambulance_broadcasts_timestamp
    BEFORE UPDATE ON ambulance_broadcasts
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS ambulance_requests (
    request_id VARCHAR(64) PRIMARY KEY,
    broadcast_id VARCHAR(64) NOT NULL REFERENCES ambulance_broadcasts(broadcast_id) ON DELETE CASCADE,
    driver_id VARCHAR(64) NOT NULL REFERENCES ambulances(ambulance_id) ON DELETE CASCADE,
    patient_id VARCHAR(64) NOT NULL,
    patient_name VARCHAR(255) NOT NULL,
    pickup_location TEXT NOT NULL,
    drop_location TEXT NOT NULL,
    contact_phone VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL CHECK (status IN ('pending', 'taken', 'accepted', 'cancelled')),
    accepted_driver_id VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_amb_requests_driver ON ambulance_requests(driver_id, status);

CREATE TABLE IF NOT EXISTS ambulance_invites (
    invite_id VARCHAR(64) PRIMARY KEY,
    token VARCHAR(255) NOT NULL UNIQUE,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    ambulance_id VARCHAR(64) NOT NULL,
    service_name VARCHAR(255) NOT NULL,
    driver_name VARCHAR(255) NOT NULL,
    phone VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled')),
    username VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ
);

-- ============================================================================
-- 18. PROMOTED ADS & SPONSORED CAMPAIGNS (WITH AWS S3 STORAGE)
-- ============================================================================

CREATE TABLE IF NOT EXISTS promoted_ads (
    ad_id VARCHAR(64) PRIMARY KEY,
    provider_type VARCHAR(32) NOT NULL CHECK (provider_type IN ('doctor', 'lab', 'pharmacy', 'ambulance')),
    provider_id VARCHAR(64) NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    image_url TEXT NOT NULL,
    image_s3_key TEXT,
    image_s3_bucket TEXT,
    image_storage_provider VARCHAR(32) DEFAULT 's3',
    cta_label VARCHAR(64) NOT NULL DEFAULT 'View Details',
    duration_hours INT NOT NULL DEFAULT 24,
    amount_paid NUMERIC(10, 2) NOT NULL DEFAULT 300.00,
    target_city VARCHAR(128),
    razorpay_order_id VARCHAR(128),
    razorpay_payment_id VARCHAR(128),
    payment_status VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'verified', 'failed')),
    status VARCHAR(32) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'pending_payment', 'active', 'expired', 'rejected')),
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_promoted_ads_active ON promoted_ads(status, target_city, end_time);
CREATE INDEX IF NOT EXISTS idx_promoted_ads_provider ON promoted_ads(provider_id);

DROP TRIGGER IF EXISTS set_promoted_ads_timestamp ON promoted_ads;
CREATE TRIGGER set_promoted_ads_timestamp
    BEFORE UPDATE ON promoted_ads
    FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ============================================================================
-- 19. IN-APP NOTIFICATIONS (RECIPIENT_UID = TEXT FIREBASE UID)
-- ============================================================================

CREATE TABLE IF NOT EXISTS in_app_notifications (
    notification_id VARCHAR(64) PRIMARY KEY,
    recipient_uid TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    body TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    type VARCHAR(32) NOT NULL DEFAULT 'system',
    target VARCHAR(64),
    target_id VARCHAR(64),
    doctor_trigger VARCHAR(64),
    patient_trigger VARCHAR(64),
    dedupe_key VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON in_app_notifications(recipient_uid, is_read, created_at DESC);

-- ============================================================================
-- 20. COMMUNITY CATALOGS
-- ============================================================================

CREATE TABLE IF NOT EXISTS community_medicines (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    name_lower VARCHAR(255) NOT NULL,
    dosage_unit VARCHAR(32) NOT NULL,
    form VARCHAR(64) NOT NULL,
    added_by_doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS community_diagnoses (
    id VARCHAR(64) PRIMARY KEY,
    text TEXT NOT NULL,
    text_lower TEXT NOT NULL,
    added_by_doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS community_lab_tests (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    name_lower VARCHAR(255) NOT NULL,
    group_name VARCHAR(128) NOT NULL,
    added_by_doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS community_radiology (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    name_lower VARCHAR(255) NOT NULL,
    group_name VARCHAR(128) NOT NULL,
    added_by_doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS community_body_parts (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    name_lower VARCHAR(255) NOT NULL,
    added_by_doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 21. SYSTEM CONFIGURATION & AUDITING (ADMIN_UID = TEXT FIREBASE UID)
-- ============================================================================

CREATE TABLE IF NOT EXISTS system_config (
    config_key VARCHAR(64) PRIMARY KEY,
    config_value JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS admin_audit_logs (
    log_id VARCHAR(64) PRIMARY KEY,
    admin_uid TEXT REFERENCES users(id) ON DELETE SET NULL,
    admin_email VARCHAR(255) NOT NULL,
    action VARCHAR(64) NOT NULL,
    target_type VARCHAR(64) NOT NULL,
    target_id VARCHAR(64) NOT NULL,
    target_name VARCHAR(255),
    details TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_target ON admin_audit_logs(target_type, target_id);

CREATE TABLE IF NOT EXISTS security_events (
    event_id VARCHAR(64) PRIMARY KEY,
    severity VARCHAR(16) NOT NULL CHECK (severity IN ('INFO', 'WARNING', 'ERROR', 'CRITICAL')),
    category VARCHAR(32) NOT NULL,
    action VARCHAR(64) NOT NULL,
    uid TEXT REFERENCES users(id) ON DELETE SET NULL,
    email_hash VARCHAR(64),
    client_ip_hash VARCHAR(64) NOT NULL,
    app_check_present BOOLEAN NOT NULL DEFAULT FALSE,
    method VARCHAR(32),
    pattern VARCHAR(64),
    detail TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL
);

-- ============================================================================
-- 22. AUTHENTICATION OTP & RATE LIMITING
-- ============================================================================

CREATE TABLE IF NOT EXISTS otp_challenges (
    challenge_id VARCHAR(128) PRIMARY KEY,
    otp_hash VARCHAR(255) NOT NULL,
    attempts INT NOT NULL DEFAULT 0,
    is_demo BOOLEAN NOT NULL DEFAULT FALSE,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS otp_verification_sessions (
    session_id VARCHAR(128) PRIMARY KEY,
    role VARCHAR(32) NOT NULL,
    target VARCHAR(255) NOT NULL,
    type VARCHAR(32) NOT NULL CHECK (type IN ('login', 'register', 'password_reset')),
    verified_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed BOOLEAN NOT NULL DEFAULT FALSE,
    consumed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS abuse_rate_limits (
    bucket VARCHAR(128) PRIMARY KEY,
    count INT NOT NULL DEFAULT 0,
    window_start TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    category VARCHAR(32) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS mail_queue (
    mail_id VARCHAR(64) PRIMARY KEY,
    to_address VARCHAR(255) NOT NULL,
    subject VARCHAR(255) NOT NULL,
    text_body TEXT,
    html_body TEXT,
    status VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sent_at TIMESTAMPTZ
);

-- ============================================================================
-- 23. SECURITY DEFINER HELPER FUNCTIONS (PURE FIREBASE JWT CLAIMS)
-- ============================================================================

-- Returns the authenticated caller's Firebase UID from the JWT 'sub' claim
CREATE OR REPLACE FUNCTION private.current_firebase_uid()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT NULLIF(auth.jwt() ->> 'sub', '');
$$;

DROP FUNCTION IF EXISTS private.current_user_id() CASCADE;
-- Returns the authenticated caller's user id (which is the Firebase UID)
CREATE OR REPLACE FUNCTION private.current_user_id()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT NULLIF(auth.jwt() ->> 'sub', '');
$$;

-- Returns the authenticated caller's application role from JWT custom claim or public.users
CREATE OR REPLACE FUNCTION private.current_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT COALESCE(
        NULLIF(auth.jwt() ->> 'user_role', ''),
        NULLIF(auth.jwt() ->> 'app_role', ''),
        (SELECT role FROM public.users WHERE id = (auth.jwt() ->> 'sub') LIMIT 1)
    );
$$;

-- Returns the caller's domain profile_id (e.g. 'd1', 'p123', 'ms_456')
CREATE OR REPLACE FUNCTION private.current_profile_id()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT profile_id FROM public.users WHERE id = (auth.jwt() ->> 'sub') LIMIT 1;
$$;

-- Evaluates Super Admin authority via custom claims, public.users role, or private.admin_users
CREATE OR REPLACE FUNCTION private.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT (
        COALESCE(auth.jwt() ->> 'user_role', auth.jwt() ->> 'app_role', '') IN ('super_admin', 'superAdmin', 'admin')
        OR EXISTS (
            SELECT 1 FROM public.users 
            WHERE id = (auth.jwt() ->> 'sub') 
              AND role IN ('super_admin', 'superAdmin', 'admin')
        )
        OR EXISTS (
            SELECT 1 FROM private.admin_users 
            WHERE user_id = (auth.jwt() ->> 'sub')
        )
    );
$$;

-- Checks if a doctor is verified by admin and not deactivated
CREATE OR REPLACE FUNCTION private.is_verified_doctor()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.doctors 
        WHERE doctor_id = private.current_profile_id() 
          AND verified = TRUE 
          AND deactivated = FALSE
    );
$$;

-- Checks if the user's profile onboarding is marked complete
CREATE OR REPLACE FUNCTION private.is_profile_completed()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT COALESCE(profile_completed, FALSE) 
    FROM public.users 
    WHERE id = (auth.jwt() ->> 'sub') 
    LIMIT 1;
$$;

-- Clinical vault access check for doctors
CREATE OR REPLACE FUNCTION private.doctor_can_access_patient(target_patient_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.patients p
        WHERE p.patient_id = target_patient_id
          AND p.share_records_with_doctors = TRUE
          AND private.is_verified_doctor()
          AND (
              p.primary_doctor_id = private.current_profile_id()
              OR p.invited_doctor_id = private.current_profile_id()
              OR private.current_profile_id() = ANY(p.care_team_doctor_ids)
              OR EXISTS (
                  SELECT 1 FROM public.patient_doctor_links pdl
                  WHERE pdl.patient_id = target_patient_id
                    AND pdl.doctor_id = private.current_profile_id()
              )
              OR EXISTS (
                  SELECT 1 FROM public.appointments a
                  WHERE a.patient_id = target_patient_id
                    AND a.doctor_id = private.current_profile_id()
              )
          )
    );
$$;

-- Public wrappers for RLS and schema queries
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT private.current_user_role();
$$;

CREATE OR REPLACE FUNCTION public.current_profile_id()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT private.current_profile_id();
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT private.is_super_admin();
$$;

CREATE OR REPLACE FUNCTION public.is_verified_doctor()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT private.is_verified_doctor();
$$;

CREATE OR REPLACE FUNCTION public.is_profile_completed()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT private.is_profile_completed();
$$;

CREATE OR REPLACE FUNCTION public.doctor_can_access_patient(target_patient_id TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT private.doctor_can_access_patient(target_patient_id);
$$;

-- Restrict function execution permissions
REVOKE ALL ON FUNCTION private.current_firebase_uid() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_firebase_uid() TO authenticated, service_role;

REVOKE ALL ON FUNCTION private.current_user_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_user_id() TO authenticated, service_role;

REVOKE ALL ON FUNCTION private.current_user_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_user_role() TO authenticated, service_role;

REVOKE ALL ON FUNCTION private.current_profile_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_profile_id() TO authenticated, service_role;

REVOKE ALL ON FUNCTION private.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_super_admin() TO authenticated, service_role;

REVOKE ALL ON FUNCTION private.is_verified_doctor() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_verified_doctor() TO authenticated, service_role;

REVOKE ALL ON FUNCTION private.is_profile_completed() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_profile_completed() TO authenticated, service_role;

REVOKE ALL ON FUNCTION private.doctor_can_access_patient(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.doctor_can_access_patient(TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_user_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_profile_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_profile_id() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.is_verified_doctor() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_verified_doctor() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.is_profile_completed() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_profile_completed() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.doctor_can_access_patient(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.doctor_can_access_patient(TEXT) TO authenticated, service_role;

-- ============================================================================
-- 24. ENABLE AND FORCE ROW-LEVEL SECURITY ON ALL TABLES
-- ============================================================================

ALTER TABLE facilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE facilities FORCE ROW LEVEL SECURITY;

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;

ALTER TABLE doctors ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctors FORCE ROW LEVEL SECURITY;

ALTER TABLE doctor_facilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctor_facilities FORCE ROW LEVEL SECURITY;

ALTER TABLE doctor_education ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctor_education FORCE ROW LEVEL SECURITY;

ALTER TABLE doctor_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctor_availability FORCE ROW LEVEL SECURITY;

ALTER TABLE doctor_blocked_dates ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctor_blocked_dates FORCE ROW LEVEL SECURITY;

ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE patients FORCE ROW LEVEL SECURITY;

ALTER TABLE patient_care_team ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_care_team FORCE ROW LEVEL SECURITY;

ALTER TABLE patient_doctor_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_doctor_links FORCE ROW LEVEL SECURITY;

ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_members FORCE ROW LEVEL SECURITY;

ALTER TABLE medical_stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE medical_stores FORCE ROW LEVEL SECURITY;

ALTER TABLE labs ENABLE ROW LEVEL SECURITY;
ALTER TABLE labs FORCE ROW LEVEL SECURITY;

ALTER TABLE lab_catalog_tests ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_catalog_tests FORCE ROW LEVEL SECURITY;

ALTER TABLE ambulances ENABLE ROW LEVEL SECURITY;
ALTER TABLE ambulances FORCE ROW LEVEL SECURITY;

ALTER TABLE ambulance_private_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE ambulance_private_settings FORCE ROW LEVEL SECURITY;

ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments FORCE ROW LEVEL SECURITY;

ALTER TABLE prescriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescriptions FORCE ROW LEVEL SECURITY;

ALTER TABLE prescription_medicines ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescription_medicines FORCE ROW LEVEL SECURITY;

ALTER TABLE prescription_investigations ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescription_investigations FORCE ROW LEVEL SECURITY;

ALTER TABLE prescription_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescription_referrals FORCE ROW LEVEL SECURITY;

ALTER TABLE health_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE health_records FORCE ROW LEVEL SECURITY;

ALTER TABLE lab_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_bookings FORCE ROW LEVEL SECURITY;

ALTER TABLE lab_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_orders FORCE ROW LEVEL SECURITY;

ALTER TABLE pharmacy_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_connections FORCE ROW LEVEL SECURITY;

ALTER TABLE lab_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_connections FORCE ROW LEVEL SECURITY;

ALTER TABLE pharmacy_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_deliveries FORCE ROW LEVEL SECURITY;

ALTER TABLE pharmacy_delivery_medicines ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_delivery_medicines FORCE ROW LEVEL SECURITY;

ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE referrals FORCE ROW LEVEL SECURITY;

ALTER TABLE medical_directory ENABLE ROW LEVEL SECURITY;
ALTER TABLE medical_directory FORCE ROW LEVEL SECURITY;

ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews FORCE ROW LEVEL SECURITY;

ALTER TABLE review_public ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_public FORCE ROW LEVEL SECURITY;

ALTER TABLE review_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_votes FORCE ROW LEVEL SECURITY;

ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets FORCE ROW LEVEL SECURITY;

ALTER TABLE support_ticket_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_ticket_messages FORCE ROW LEVEL SECURITY;

ALTER TABLE ambulance_broadcasts ENABLE ROW LEVEL SECURITY;
ALTER TABLE ambulance_broadcasts FORCE ROW LEVEL SECURITY;

ALTER TABLE ambulance_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE ambulance_requests FORCE ROW LEVEL SECURITY;

ALTER TABLE ambulance_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE ambulance_invites FORCE ROW LEVEL SECURITY;

ALTER TABLE promoted_ads ENABLE ROW LEVEL SECURITY;
ALTER TABLE promoted_ads FORCE ROW LEVEL SECURITY;

ALTER TABLE in_app_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE in_app_notifications FORCE ROW LEVEL SECURITY;

ALTER TABLE community_medicines ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_medicines FORCE ROW LEVEL SECURITY;

ALTER TABLE community_diagnoses ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_diagnoses FORCE ROW LEVEL SECURITY;

ALTER TABLE community_lab_tests ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_lab_tests FORCE ROW LEVEL SECURITY;

ALTER TABLE community_radiology ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_radiology FORCE ROW LEVEL SECURITY;

ALTER TABLE community_body_parts ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_body_parts FORCE ROW LEVEL SECURITY;

ALTER TABLE system_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_config FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_audit_logs FORCE ROW LEVEL SECURITY;

ALTER TABLE security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_events FORCE ROW LEVEL SECURITY;

ALTER TABLE otp_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE otp_challenges FORCE ROW LEVEL SECURITY;

ALTER TABLE otp_verification_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE otp_verification_sessions FORCE ROW LEVEL SECURITY;

ALTER TABLE abuse_rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE abuse_rate_limits FORCE ROW LEVEL SECURITY;

ALTER TABLE mail_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE mail_queue FORCE ROW LEVEL SECURITY;

ALTER TABLE private.admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.admin_users FORCE ROW LEVEL SECURITY;

-- ============================================================================
-- 25. ROW-LEVEL SECURITY POLICIES BY MODULE
-- ============================================================================

-- ----------------------------------------------------------------------------
-- MODULE: CORE & FACILITIES
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "facilities_select_auth" ON facilities;
CREATE POLICY "facilities_select_auth" ON facilities
    FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "facilities_write_admin" ON facilities;
CREATE POLICY "facilities_write_admin" ON facilities
    FOR ALL TO authenticated 
    USING (private.is_super_admin()) 
    WITH CHECK (private.is_super_admin());

DROP POLICY IF EXISTS "users_select_owner_or_admin" ON users;
CREATE POLICY "users_select_owner_or_admin" ON users
    FOR SELECT TO authenticated
    USING (id = (auth.jwt() ->> 'sub') OR private.is_super_admin());

DROP POLICY IF EXISTS "users_insert_self_or_admin" ON users;
CREATE POLICY "users_insert_self_or_admin" ON users
    FOR INSERT TO authenticated
    WITH CHECK (id = (auth.jwt() ->> 'sub') OR private.is_super_admin());

DROP POLICY IF EXISTS "users_update_owner_or_admin" ON users;
CREATE POLICY "users_update_owner_or_admin" ON users
    FOR UPDATE TO authenticated
    USING (id = (auth.jwt() ->> 'sub') OR private.is_super_admin())
    WITH CHECK (
        private.is_super_admin() 
        OR (
            id = (auth.jwt() ->> 'sub') 
            AND role = (SELECT role FROM users WHERE id = (auth.jwt() ->> 'sub'))
            AND verified = (SELECT verified FROM users WHERE id = (auth.jwt() ->> 'sub'))
        )
    );

DROP POLICY IF EXISTS "users_delete_admin" ON users;
CREATE POLICY "users_delete_admin" ON users
    FOR DELETE TO authenticated USING (private.is_super_admin());

-- ----------------------------------------------------------------------------
-- MODULE: DOCTORS
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "doctors_select" ON doctors;
CREATE POLICY "doctors_select" ON doctors
    FOR SELECT TO authenticated
    USING (
        verified = TRUE 
        OR owner_uid = (auth.jwt() ->> 'sub') 
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "doctors_insert" ON doctors;
CREATE POLICY "doctors_insert" ON doctors
    FOR INSERT TO authenticated
    WITH CHECK (
        (owner_uid = (auth.jwt() ->> 'sub') AND verified = FALSE) 
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "doctors_update" ON doctors;
CREATE POLICY "doctors_update" ON doctors
    FOR UPDATE TO authenticated
    USING (owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin())
    WITH CHECK (
        private.is_super_admin()
        OR (
            owner_uid = (auth.jwt() ->> 'sub')
            AND verified = (SELECT verified FROM doctors WHERE doctor_id = private.current_profile_id())
            AND rating = (SELECT rating FROM doctors WHERE doctor_id = private.current_profile_id())
            AND review_count = (SELECT review_count FROM doctors WHERE doctor_id = private.current_profile_id())
        )
    );

DROP POLICY IF EXISTS "doctors_delete_admin" ON doctors;
CREATE POLICY "doctors_delete_admin" ON doctors
    FOR DELETE TO authenticated USING (private.is_super_admin());

-- Doctor Sub-tables
DROP POLICY IF EXISTS "doc_facilities_select" ON doctor_facilities;
CREATE POLICY "doc_facilities_select" ON doctor_facilities FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "doc_facilities_write" ON doctor_facilities;
CREATE POLICY "doc_facilities_write" ON doctor_facilities FOR ALL TO authenticated
    USING (doctor_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (doctor_id = private.current_profile_id() OR private.is_super_admin());

DROP POLICY IF EXISTS "doc_education_select" ON doctor_education;
CREATE POLICY "doc_education_select" ON doctor_education FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "doc_education_write" ON doctor_education;
CREATE POLICY "doc_education_write" ON doctor_education FOR ALL TO authenticated
    USING (doctor_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (doctor_id = private.current_profile_id() OR private.is_super_admin());

DROP POLICY IF EXISTS "doc_avail_select" ON doctor_availability;
CREATE POLICY "doc_avail_select" ON doctor_availability FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "doc_avail_write" ON doctor_availability;
CREATE POLICY "doc_avail_write" ON doctor_availability FOR ALL TO authenticated
    USING (doctor_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (doctor_id = private.current_profile_id() OR private.is_super_admin());

DROP POLICY IF EXISTS "doc_blocked_select" ON doctor_blocked_dates;
CREATE POLICY "doc_blocked_select" ON doctor_blocked_dates FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "doc_blocked_write" ON doctor_blocked_dates;
CREATE POLICY "doc_blocked_write" ON doctor_blocked_dates FOR ALL TO authenticated
    USING (doctor_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (doctor_id = private.current_profile_id() OR private.is_super_admin());

-- ----------------------------------------------------------------------------
-- MODULE: PATIENTS
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "patients_select" ON patients;
CREATE POLICY "patients_select" ON patients
    FOR SELECT TO authenticated
    USING (
        owner_uid = (auth.jwt() ->> 'sub')
        OR private.doctor_can_access_patient(patient_id)
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "patients_insert" ON patients;
CREATE POLICY "patients_insert" ON patients
    FOR INSERT TO authenticated
    WITH CHECK (owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin());

DROP POLICY IF EXISTS "patients_update" ON patients;
CREATE POLICY "patients_update" ON patients
    FOR UPDATE TO authenticated
    USING (owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin())
    WITH CHECK (owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin());

DROP POLICY IF EXISTS "patients_delete_admin" ON patients;
CREATE POLICY "patients_delete_admin" ON patients
    FOR DELETE TO authenticated USING (private.is_super_admin());

-- Patient Sub-tables
DROP POLICY IF EXISTS "family_members_owner" ON family_members;
CREATE POLICY "family_members_owner" ON family_members
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM patients p 
            WHERE p.patient_id = family_members.patient_id 
              AND (p.owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin())
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM patients p 
            WHERE p.patient_id = family_members.patient_id 
              AND (p.owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin())
        )
    );

DROP POLICY IF EXISTS "patient_care_team_select" ON patient_care_team;
CREATE POLICY "patient_care_team_select" ON patient_care_team
    FOR SELECT TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM patients p 
            WHERE p.patient_id = patient_care_team.patient_id 
              AND p.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "patient_care_team_write" ON patient_care_team;
CREATE POLICY "patient_care_team_write" ON patient_care_team
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM patients p 
            WHERE p.patient_id = patient_care_team.patient_id 
              AND (p.owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin())
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM patients p 
            WHERE p.patient_id = patient_care_team.patient_id 
              AND (p.owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin())
        )
    );

DROP POLICY IF EXISTS "pdl_select" ON patient_doctor_links;
CREATE POLICY "pdl_select" ON patient_doctor_links
    FOR SELECT TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM patients p 
            WHERE p.patient_id = patient_doctor_links.patient_id 
              AND p.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR private.is_super_admin()
    );

-- ----------------------------------------------------------------------------
-- MODULE: APPOINTMENTS
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "appointments_select" ON appointments;
CREATE POLICY "appointments_select" ON appointments
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "appointments_insert" ON appointments;
CREATE POLICY "appointments_insert" ON appointments
    FOR INSERT TO authenticated
    WITH CHECK (
        patient_id = private.current_profile_id()
        OR (doctor_id = private.current_profile_id() AND source = 'walkin')
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "appointments_update" ON appointments;
CREATE POLICY "appointments_update" ON appointments
    FOR UPDATE TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        doctor_id = private.current_profile_id()
        OR (
            patient_id = private.current_profile_id()
            AND patient_status = 'cancelled'
        )
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "appointments_delete_admin" ON appointments;
CREATE POLICY "appointments_delete_admin" ON appointments
    FOR DELETE TO authenticated USING (private.is_super_admin());

-- ----------------------------------------------------------------------------
-- MODULE: PRESCRIPTIONS
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "prescriptions_select" ON prescriptions;
CREATE POLICY "prescriptions_select" ON prescriptions
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM pharmacy_deliveries pd 
            WHERE pd.prescription_id = prescriptions.prescription_id 
              AND pd.store_id = private.current_profile_id()
        )
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "prescriptions_insert" ON prescriptions;
CREATE POLICY "prescriptions_insert" ON prescriptions
    FOR INSERT TO authenticated
    WITH CHECK (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "prescriptions_update" ON prescriptions;
CREATE POLICY "prescriptions_update" ON prescriptions
    FOR UPDATE TO authenticated
    USING (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    )
    WITH CHECK (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "prescriptions_delete_admin" ON prescriptions;
CREATE POLICY "prescriptions_delete_admin" ON prescriptions
    FOR DELETE TO authenticated USING (private.is_super_admin());

-- Prescription Lines
DROP POLICY IF EXISTS "presc_meds_select" ON prescription_medicines;
CREATE POLICY "presc_meds_select" ON prescription_medicines FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM prescriptions p 
            WHERE p.prescription_id = prescription_medicines.prescription_id 
              AND (
                  p.patient_id = private.current_profile_id()
                  OR p.doctor_id = private.current_profile_id()
                  OR EXISTS (
                      SELECT 1 FROM pharmacy_deliveries pd 
                      WHERE pd.prescription_id = p.prescription_id 
                        AND pd.store_id = private.current_profile_id()
                  )
                  OR private.is_super_admin()
              )
        )
    );

DROP POLICY IF EXISTS "presc_meds_write" ON prescription_medicines;
CREATE POLICY "presc_meds_write" ON prescription_medicines FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM prescriptions p 
            WHERE p.prescription_id = prescription_medicines.prescription_id 
              AND (p.doctor_id = private.current_profile_id() OR private.is_super_admin())
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM prescriptions p 
            WHERE p.prescription_id = prescription_medicines.prescription_id 
              AND (p.doctor_id = private.current_profile_id() OR private.is_super_admin())
        )
    );

DROP POLICY IF EXISTS "presc_inv_select" ON prescription_investigations;
CREATE POLICY "presc_inv_select" ON prescription_investigations FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM prescriptions p 
            WHERE p.prescription_id = prescription_investigations.prescription_id 
              AND (
                  p.patient_id = private.current_profile_id()
                  OR p.doctor_id = private.current_profile_id()
                  OR private.is_super_admin()
              )
        )
    );

DROP POLICY IF EXISTS "presc_inv_write" ON prescription_investigations;
CREATE POLICY "presc_inv_write" ON prescription_investigations FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM prescriptions p 
            WHERE p.prescription_id = prescription_investigations.prescription_id 
              AND (p.doctor_id = private.current_profile_id() OR private.is_super_admin())
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM prescriptions p 
            WHERE p.prescription_id = prescription_investigations.prescription_id 
              AND (p.doctor_id = private.current_profile_id() OR private.is_super_admin())
        )
    );

DROP POLICY IF EXISTS "presc_ref_select" ON prescription_referrals;
CREATE POLICY "presc_ref_select" ON prescription_referrals FOR SELECT TO authenticated
    USING (
        to_doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM prescriptions p 
            WHERE p.prescription_id = prescription_referrals.prescription_id 
              AND (
                  p.patient_id = private.current_profile_id()
                  OR p.doctor_id = private.current_profile_id()
                  OR private.is_super_admin()
              )
        )
    );

DROP POLICY IF EXISTS "presc_ref_write" ON prescription_referrals;
CREATE POLICY "presc_ref_write" ON prescription_referrals FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM prescriptions p 
            WHERE p.prescription_id = prescription_referrals.prescription_id 
              AND (p.doctor_id = private.current_profile_id() OR private.is_super_admin())
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM prescriptions p 
            WHERE p.prescription_id = prescription_referrals.prescription_id 
              AND (p.doctor_id = private.current_profile_id() OR private.is_super_admin())
        )
    );

-- ----------------------------------------------------------------------------
-- MODULE: HEALTH RECORDS (CLINICAL VAULT)
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "health_records_select" ON health_records;
CREATE POLICY "health_records_select" ON health_records
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR (
            private.doctor_can_access_patient(patient_id)
            AND (shared_with_doctors = TRUE OR source = 'doctorPrescribed')
        )
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "health_records_insert" ON health_records;
CREATE POLICY "health_records_insert" ON health_records
    FOR INSERT TO authenticated
    WITH CHECK (
        (patient_id = private.current_profile_id() AND source = 'selfUploaded')
        OR (private.doctor_can_access_patient(patient_id) AND source = 'doctorPrescribed')
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "health_records_update" ON health_records;
CREATE POLICY "health_records_update" ON health_records
    FOR UPDATE TO authenticated
    USING (patient_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (patient_id = private.current_profile_id() OR private.is_super_admin());

DROP POLICY IF EXISTS "health_records_delete" ON health_records;
CREATE POLICY "health_records_delete" ON health_records
    FOR DELETE TO authenticated
    USING (patient_id = private.current_profile_id() OR private.is_super_admin());

-- ----------------------------------------------------------------------------
-- MODULE: PHARMACY (MEDICAL STORES)
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "medical_stores_select" ON medical_stores;
CREATE POLICY "medical_stores_select" ON medical_stores
    FOR SELECT TO authenticated
    USING (
        verified = TRUE 
        OR owner_uid = (auth.jwt() ->> 'sub') 
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "medical_stores_insert" ON medical_stores;
CREATE POLICY "medical_stores_insert" ON medical_stores
    FOR INSERT TO authenticated
    WITH CHECK (
        (owner_uid = (auth.jwt() ->> 'sub') AND verified = FALSE) 
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "medical_stores_update" ON medical_stores;
CREATE POLICY "medical_stores_update" ON medical_stores
    FOR UPDATE TO authenticated
    USING (owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin())
    WITH CHECK (
        private.is_super_admin()
        OR (
            owner_uid = (auth.jwt() ->> 'sub')
            AND verified = (SELECT verified FROM medical_stores WHERE store_id = private.current_profile_id())
        )
    );

DROP POLICY IF EXISTS "medical_stores_delete_admin" ON medical_stores;
CREATE POLICY "medical_stores_delete_admin" ON medical_stores
    FOR DELETE TO authenticated USING (private.is_super_admin());

DROP POLICY IF EXISTS "pharmacy_connections_select" ON pharmacy_connections;
CREATE POLICY "pharmacy_connections_select" ON pharmacy_connections
    FOR SELECT TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR medical_store_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "pharmacy_connections_write" ON pharmacy_connections;
CREATE POLICY "pharmacy_connections_write" ON pharmacy_connections
    FOR ALL TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR medical_store_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        doctor_id = private.current_profile_id()
        OR medical_store_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "pharmacy_deliveries_select" ON pharmacy_deliveries;
CREATE POLICY "pharmacy_deliveries_select" ON pharmacy_deliveries
    FOR SELECT TO authenticated
    USING (
        store_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "pharmacy_deliveries_insert" ON pharmacy_deliveries;
CREATE POLICY "pharmacy_deliveries_insert" ON pharmacy_deliveries
    FOR INSERT TO authenticated
    WITH CHECK (
        doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "pharmacy_deliveries_update" ON pharmacy_deliveries;
CREATE POLICY "pharmacy_deliveries_update" ON pharmacy_deliveries
    FOR UPDATE TO authenticated
    USING (
        store_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        store_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "pharmacy_delivery_meds_select" ON pharmacy_delivery_medicines;
CREATE POLICY "pharmacy_delivery_meds_select" ON pharmacy_delivery_medicines
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM pharmacy_deliveries pd 
            WHERE pd.delivery_id = pharmacy_delivery_medicines.delivery_id 
              AND (
                  pd.store_id = private.current_profile_id()
                  OR pd.doctor_id = private.current_profile_id()
                  OR pd.patient_id = private.current_profile_id()
                  OR private.is_super_admin()
              )
        )
    );

DROP POLICY IF EXISTS "pharmacy_delivery_meds_write" ON pharmacy_delivery_medicines;
CREATE POLICY "pharmacy_delivery_meds_write" ON pharmacy_delivery_medicines
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM pharmacy_deliveries pd 
            WHERE pd.delivery_id = pharmacy_delivery_medicines.delivery_id 
              AND (pd.store_id = private.current_profile_id() OR private.is_super_admin())
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM pharmacy_deliveries pd 
            WHERE pd.delivery_id = pharmacy_delivery_medicines.delivery_id 
              AND (pd.store_id = private.current_profile_id() OR private.is_super_admin())
        )
    );

-- ----------------------------------------------------------------------------
-- MODULE: DIAGNOSTIC LABS
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "labs_select" ON labs;
CREATE POLICY "labs_select" ON labs
    FOR SELECT TO authenticated
    USING (
        verified = TRUE 
        OR owner_uid = (auth.jwt() ->> 'sub') 
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "labs_insert" ON labs;
CREATE POLICY "labs_insert" ON labs
    FOR INSERT TO authenticated
    WITH CHECK (
        (owner_uid = (auth.jwt() ->> 'sub') AND verified = FALSE) 
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "labs_update" ON labs;
CREATE POLICY "labs_update" ON labs
    FOR UPDATE TO authenticated
    USING (owner_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin())
    WITH CHECK (
        private.is_super_admin()
        OR (
            owner_uid = (auth.jwt() ->> 'sub')
            AND verified = (SELECT verified FROM labs WHERE lab_id = private.current_profile_id())
        )
    );

DROP POLICY IF EXISTS "labs_delete_admin" ON labs;
CREATE POLICY "labs_delete_admin" ON labs
    FOR DELETE TO authenticated USING (private.is_super_admin());

DROP POLICY IF EXISTS "lab_catalog_tests_select" ON lab_catalog_tests;
CREATE POLICY "lab_catalog_tests_select" ON lab_catalog_tests FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "lab_catalog_tests_write" ON lab_catalog_tests;
CREATE POLICY "lab_catalog_tests_write" ON lab_catalog_tests FOR ALL TO authenticated
    USING (private.is_super_admin()) WITH CHECK (private.is_super_admin());

DROP POLICY IF EXISTS "lab_connections_select" ON lab_connections;
CREATE POLICY "lab_connections_select" ON lab_connections
    FOR SELECT TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "lab_connections_write" ON lab_connections;
CREATE POLICY "lab_connections_write" ON lab_connections
    FOR ALL TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        doctor_id = private.current_profile_id()
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "lab_bookings_select" ON lab_bookings;
CREATE POLICY "lab_bookings_select" ON lab_bookings
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "lab_bookings_insert" ON lab_bookings;
CREATE POLICY "lab_bookings_insert" ON lab_bookings
    FOR INSERT TO authenticated
    WITH CHECK (
        patient_id = private.current_profile_id()
        OR (lab_id = private.current_profile_id() AND source = 'walkin')
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "lab_bookings_update" ON lab_bookings;
CREATE POLICY "lab_bookings_update" ON lab_bookings
    FOR UPDATE TO authenticated
    USING (
        lab_id = private.current_profile_id()
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        lab_id = private.current_profile_id()
        OR (patient_id = private.current_profile_id() AND status = 'cancelled')
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "lab_orders_select" ON lab_orders;
CREATE POLICY "lab_orders_select" ON lab_orders
    FOR SELECT TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR patient_id = private.current_profile_id()
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "lab_orders_insert" ON lab_orders;
CREATE POLICY "lab_orders_insert" ON lab_orders
    FOR INSERT TO authenticated
    WITH CHECK (
        doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "lab_orders_update" ON lab_orders;
CREATE POLICY "lab_orders_update" ON lab_orders
    FOR UPDATE TO authenticated
    USING (
        lab_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        lab_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- ----------------------------------------------------------------------------
-- MODULE: AMBULANCES
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "ambulances_select" ON ambulances;
CREATE POLICY "ambulances_select" ON ambulances
    FOR SELECT TO authenticated
    USING (
        verified = TRUE 
        OR auth_uid = (auth.jwt() ->> 'sub') 
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "ambulances_update" ON ambulances;
CREATE POLICY "ambulances_update" ON ambulances
    FOR UPDATE TO authenticated
    USING (auth_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin())
    WITH CHECK (
        private.is_super_admin()
        OR (
            auth_uid = (auth.jwt() ->> 'sub')
            AND verified = (SELECT verified FROM ambulances WHERE ambulance_id = private.current_profile_id())
        )
    );

DROP POLICY IF EXISTS "ambulance_private_settings_access" ON ambulance_private_settings;
CREATE POLICY "ambulance_private_settings_access" ON ambulance_private_settings
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM ambulances a 
            WHERE a.ambulance_id = ambulance_private_settings.ambulance_id 
              AND (a.auth_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin())
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM ambulances a 
            WHERE a.ambulance_id = ambulance_private_settings.ambulance_id 
              AND (a.auth_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin())
        )
    );

DROP POLICY IF EXISTS "amb_broadcasts_select" ON ambulance_broadcasts;
CREATE POLICY "amb_broadcasts_select" ON ambulance_broadcasts
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR accepted_driver_id = private.current_profile_id()
        OR (
            private.current_user_role() = 'ambulance' 
            AND status = 'pending'
        )
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "amb_broadcasts_insert" ON ambulance_broadcasts;
CREATE POLICY "amb_broadcasts_insert" ON ambulance_broadcasts
    FOR INSERT TO authenticated
    WITH CHECK (
        patient_id = private.current_profile_id() 
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "amb_broadcasts_update" ON ambulance_broadcasts;
CREATE POLICY "amb_broadcasts_update" ON ambulance_broadcasts
    FOR UPDATE TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR accepted_driver_id = private.current_profile_id()
        OR (private.current_user_role() = 'ambulance' AND status = 'pending')
        OR private.is_super_admin()
    )
    WITH CHECK (
        accepted_driver_id = private.current_profile_id()
        OR (patient_id = private.current_profile_id() AND status = 'cancelled')
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "amb_requests_select" ON ambulance_requests;
CREATE POLICY "amb_requests_select" ON ambulance_requests
    FOR SELECT TO authenticated
    USING (
        driver_id = private.current_profile_id()
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "amb_requests_update" ON ambulance_requests;
CREATE POLICY "amb_requests_update" ON ambulance_requests
    FOR UPDATE TO authenticated
    USING (driver_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (driver_id = private.current_profile_id() OR private.is_super_admin());

DROP POLICY IF EXISTS "amb_invites_select" ON ambulance_invites;
CREATE POLICY "amb_invites_select" ON ambulance_invites
    FOR SELECT TO authenticated
    USING (doctor_id = private.current_profile_id() OR private.is_super_admin());

DROP POLICY IF EXISTS "amb_invites_write" ON ambulance_invites;
CREATE POLICY "amb_invites_write" ON ambulance_invites
    FOR ALL TO authenticated
    USING (doctor_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (doctor_id = private.current_profile_id() OR private.is_super_admin());

-- ----------------------------------------------------------------------------
-- MODULE: NOTIFICATIONS & PROMOTIONS
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "notifications_select" ON in_app_notifications;
CREATE POLICY "notifications_select" ON in_app_notifications
    FOR SELECT TO authenticated
    USING (recipient_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin());

DROP POLICY IF EXISTS "notifications_update" ON in_app_notifications;
CREATE POLICY "notifications_update" ON in_app_notifications
    FOR UPDATE TO authenticated
    USING (recipient_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin())
    WITH CHECK (recipient_uid = (auth.jwt() ->> 'sub') OR private.is_super_admin());

DROP POLICY IF EXISTS "promoted_ads_select" ON promoted_ads;
CREATE POLICY "promoted_ads_select" ON promoted_ads
    FOR SELECT TO authenticated
    USING (
        status = 'active'
        OR provider_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "promoted_ads_write" ON promoted_ads;
CREATE POLICY "promoted_ads_write" ON promoted_ads
    FOR ALL TO authenticated
    USING (provider_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (provider_id = private.current_profile_id() OR private.is_super_admin());

-- ----------------------------------------------------------------------------
-- MODULE: DIRECTORY, REVIEWS, REFERRALS & SUPPORT
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "referrals_select" ON referrals;
CREATE POLICY "referrals_select" ON referrals
    FOR SELECT TO authenticated
    USING (
        from_doctor_id = private.current_profile_id()
        OR to_doctor_id = private.current_profile_id()
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "referrals_write" ON referrals;
CREATE POLICY "referrals_write" ON referrals
    FOR ALL TO authenticated
    USING (
        from_doctor_id = private.current_profile_id() 
        OR to_doctor_id = private.current_profile_id() 
        OR private.is_super_admin()
    )
    WITH CHECK (
        from_doctor_id = private.current_profile_id() 
        OR to_doctor_id = private.current_profile_id() 
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "med_directory_select" ON medical_directory;
CREATE POLICY "med_directory_select" ON medical_directory FOR SELECT TO authenticated
    USING (doctor_id = private.current_profile_id() OR private.is_super_admin());

DROP POLICY IF EXISTS "med_directory_write" ON medical_directory;
CREATE POLICY "med_directory_write" ON medical_directory FOR ALL TO authenticated
    USING (doctor_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (doctor_id = private.current_profile_id() OR private.is_super_admin());

DROP POLICY IF EXISTS "reviews_select" ON reviews;
CREATE POLICY "reviews_select" ON reviews FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "reviews_insert" ON reviews;
CREATE POLICY "reviews_insert" ON reviews FOR INSERT TO authenticated
    WITH CHECK (patient_id = private.current_profile_id() OR private.is_super_admin());

DROP POLICY IF EXISTS "reviews_update" ON reviews;
CREATE POLICY "reviews_update" ON reviews FOR UPDATE TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "review_public_select" ON review_public;
CREATE POLICY "review_public_select" ON review_public FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "review_votes_select" ON review_votes;
CREATE POLICY "review_votes_select" ON review_votes FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "review_votes_write" ON review_votes;
CREATE POLICY "review_votes_write" ON review_votes FOR ALL TO authenticated
    USING (patient_id = private.current_profile_id() OR private.is_super_admin())
    WITH CHECK (patient_id = private.current_profile_id() OR private.is_super_admin());

DROP POLICY IF EXISTS "support_tickets_select" ON support_tickets;
CREATE POLICY "support_tickets_select" ON support_tickets FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "support_tickets_write" ON support_tickets;
CREATE POLICY "support_tickets_write" ON support_tickets FOR ALL TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "support_messages_select" ON support_ticket_messages;
CREATE POLICY "support_messages_select" ON support_ticket_messages FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM support_tickets st 
            WHERE st.ticket_id = support_ticket_messages.ticket_id 
              AND (
                  st.patient_id = private.current_profile_id()
                  OR st.doctor_id = private.current_profile_id()
                  OR private.is_super_admin()
              )
        )
    );

DROP POLICY IF EXISTS "support_messages_insert" ON support_ticket_messages;
CREATE POLICY "support_messages_insert" ON support_ticket_messages FOR INSERT TO authenticated
    WITH CHECK (
        sender_id = (auth.jwt() ->> 'sub')
        OR private.is_super_admin()
    );

-- ----------------------------------------------------------------------------
-- MODULE: COMMUNITY CATALOGS
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "comm_meds_select" ON community_medicines;
CREATE POLICY "comm_meds_select" ON community_medicines FOR SELECT TO authenticated USING (TRUE);
DROP POLICY IF EXISTS "comm_meds_insert" ON community_medicines;
CREATE POLICY "comm_meds_insert" ON community_medicines FOR INSERT TO authenticated
    WITH CHECK (private.is_verified_doctor() OR private.is_super_admin());

DROP POLICY IF EXISTS "comm_diag_select" ON community_diagnoses;
CREATE POLICY "comm_diag_select" ON community_diagnoses FOR SELECT TO authenticated USING (TRUE);
DROP POLICY IF EXISTS "comm_diag_insert" ON community_diagnoses;
CREATE POLICY "comm_diag_insert" ON community_diagnoses FOR INSERT TO authenticated
    WITH CHECK (private.is_verified_doctor() OR private.is_super_admin());

DROP POLICY IF EXISTS "comm_tests_select" ON community_lab_tests;
CREATE POLICY "comm_tests_select" ON community_lab_tests FOR SELECT TO authenticated USING (TRUE);
DROP POLICY IF EXISTS "comm_tests_insert" ON community_lab_tests;
CREATE POLICY "comm_tests_insert" ON community_lab_tests FOR INSERT TO authenticated
    WITH CHECK (private.is_verified_doctor() OR private.is_super_admin());

DROP POLICY IF EXISTS "comm_rad_select" ON community_radiology;
CREATE POLICY "comm_rad_select" ON community_radiology FOR SELECT TO authenticated USING (TRUE);
DROP POLICY IF EXISTS "comm_rad_insert" ON community_radiology;
CREATE POLICY "comm_rad_insert" ON community_radiology FOR INSERT TO authenticated
    WITH CHECK (private.is_verified_doctor() OR private.is_super_admin());

DROP POLICY IF EXISTS "comm_body_select" ON community_body_parts;
CREATE POLICY "comm_body_select" ON community_body_parts FOR SELECT TO authenticated USING (TRUE);
DROP POLICY IF EXISTS "comm_body_insert" ON community_body_parts;
CREATE POLICY "comm_body_insert" ON community_body_parts FOR INSERT TO authenticated
    WITH CHECK (private.is_verified_doctor() OR private.is_super_admin());

-- ----------------------------------------------------------------------------
-- MODULE: SYSTEM CONFIG, AUDIT LOGS & INFRASTRUCTURE
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "system_config_select" ON system_config;
CREATE POLICY "system_config_select" ON system_config FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "system_config_write" ON system_config;
CREATE POLICY "system_config_write" ON system_config FOR ALL TO authenticated
    USING (private.is_super_admin()) WITH CHECK (private.is_super_admin());

DROP POLICY IF EXISTS "admin_audit_logs_select" ON admin_audit_logs;
CREATE POLICY "admin_audit_logs_select" ON admin_audit_logs FOR SELECT TO authenticated
    USING (private.is_super_admin());

DROP POLICY IF EXISTS "admin_audit_logs_insert" ON admin_audit_logs;
CREATE POLICY "admin_audit_logs_insert" ON admin_audit_logs FOR INSERT TO authenticated
    WITH CHECK (private.is_super_admin());

DROP POLICY IF EXISTS "security_events_admin" ON security_events;
CREATE POLICY "security_events_admin" ON security_events FOR ALL TO authenticated
    USING (private.is_super_admin()) WITH CHECK (private.is_super_admin());

-- OTP challenges, verification sessions, abuse rate limits & mail queue
-- Completely locked down from public/authenticated direct REST access. Only service_role.
REVOKE ALL ON TABLE otp_challenges FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE otp_challenges TO service_role;

REVOKE ALL ON TABLE otp_verification_sessions FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE otp_verification_sessions TO service_role;

REVOKE ALL ON TABLE abuse_rate_limits FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE abuse_rate_limits TO service_role;

REVOKE ALL ON TABLE mail_queue FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE mail_queue TO service_role;
