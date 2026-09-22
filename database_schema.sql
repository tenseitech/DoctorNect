-- ============================================================================
-- DOCTORNECT PLATFORM — COMPLETE RELATIONAL DATABASE SCHEMA (PostgreSQL 14+)
-- ============================================================================
-- Database: doctornect_db
-- Description: Full production-grade DDL defining all tables, primary keys,
-- foreign keys, check constraints, indexes, and relationship cascades for
-- the DoctorNect telehealth, consultation, diagnostics, pharmacy & ambulance ecosystem.
-- ============================================================================

-- 0. DATABASE CREATION (Run individually or connect to target DB)
-- CREATE DATABASE doctornect_db WITH ENCODING 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';
-- \c doctornect_db;

-- Enable UUID extension if UUID generation is required
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- 1. AUTHENTICATION & CORE IDENTITY
-- ============================================================================

CREATE TABLE IF NOT EXISTS users (
    uid VARCHAR(128) PRIMARY KEY,
    role VARCHAR(32) NOT NULL CHECK (role IN ('super_admin', 'superAdmin', 'admin', 'doctor', 'patient', 'medicalStore', 'lab', 'ambulance')),
    profile_id VARCHAR(64) NOT NULL,
    display_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    mobile VARCHAR(32),
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMPTZ,
    deactivated BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(32) DEFAULT 'approved',
    photo_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_mobile ON users(mobile);
CREATE INDEX idx_users_profile_id ON users(profile_id);

-- ============================================================================
-- 2. HEALTHCARE PROVIDERS: DOCTORS
-- ============================================================================

CREATE TABLE IF NOT EXISTS doctors (
    doctor_id VARCHAR(64) PRIMARY KEY,
    owner_uid VARCHAR(128) REFERENCES users(uid) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    mobile VARCHAR(32) NOT NULL,
    specialization VARCHAR(128) NOT NULL,
    super_specialization TEXT,
    qualification VARCHAR(255) NOT NULL,
    experience_years INT NOT NULL DEFAULT 1,
    consultation_fee NUMERIC(10, 2) DEFAULT 0.00,
    clinic_name VARCHAR(255),
    area VARCHAR(128),
    city VARCHAR(128),
    state VARCHAR(128),
    country VARCHAR(64) DEFAULT 'India',
    pincode VARCHAR(16),
    address_line1 TEXT,
    address_line2 TEXT,
    state_council VARCHAR(255),
    council_number VARCHAR(128),
    about TEXT,
    languages TEXT[] DEFAULT ARRAY['English', 'Hindi']::TEXT[],
    photo_url TEXT,
    maps_link TEXT,
    landmark VARCHAR(255),
    rating NUMERIC(3, 2) NOT NULL DEFAULT 0.00,
    review_count INT NOT NULL DEFAULT 0,
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

CREATE INDEX idx_doctors_verified_city ON doctors(verified, city);
CREATE INDEX idx_doctors_specialization ON doctors(specialization);
CREATE INDEX idx_doctors_owner_uid ON doctors(owner_uid);
CREATE INDEX idx_doctors_rating ON doctors(rating DESC);

-- Doctor Education Degrees
CREATE TABLE IF NOT EXISTS doctor_education (
    id BIGSERIAL PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    degree VARCHAR(128) NOT NULL,
    college VARCHAR(255),
    year INT
);

CREATE INDEX idx_doctor_education_doctor ON doctor_education(doctor_id);

-- Doctor Weekly Schedule & Availability
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

-- Doctor Blocked Specific Dates
CREATE TABLE IF NOT EXISTS doctor_blocked_dates (
    id BIGSERIAL PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    blocked_date DATE NOT NULL,
    UNIQUE(doctor_id, blocked_date)
);

CREATE INDEX idx_doctor_blocked_dates ON doctor_blocked_dates(doctor_id, blocked_date);

-- ============================================================================
-- 3. PATIENTS & FAMILY HEALTH PROFILES
-- ============================================================================

CREATE TABLE IF NOT EXISTS patients (
    patient_id VARCHAR(64) PRIMARY KEY,
    owner_uid VARCHAR(128) REFERENCES users(uid) ON DELETE SET NULL,
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
    share_records_with_doctors BOOLEAN NOT NULL DEFAULT TRUE,
    primary_doctor_id VARCHAR(64) REFERENCES doctors(doctor_id) ON DELETE SET NULL,
    invited_doctor_id VARCHAR(64) REFERENCES doctors(doctor_id) ON DELETE SET NULL,
    verified BOOLEAN NOT NULL DEFAULT TRUE,
    fcm_token TEXT,
    fcm_token_updated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_patients_owner_uid ON patients(owner_uid);
CREATE INDEX idx_patients_mobile ON patients(mobile);

-- Patient Care Team Junction (Authorized doctors with access to patient clinical vault)
CREATE TABLE IF NOT EXISTS patient_care_team (
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (patient_id, doctor_id)
);

CREATE INDEX idx_care_team_doctor ON patient_care_team(doctor_id);

-- Patient Doctor Links (Audit-proof relationship links created on booking or referral)
CREATE TABLE IF NOT EXISTS patient_doctor_links (
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    source VARCHAR(32) NOT NULL CHECK (source IN ('appointment', 'referral', 'manual')),
    from_doctor_id VARCHAR(64) REFERENCES doctors(doctor_id) ON DELETE SET NULL,
    referral_id VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (patient_id, doctor_id)
);

-- Family Members (Dependents under a Patient account)
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

CREATE INDEX idx_family_members_patient ON family_members(patient_id);

-- ============================================================================
-- 4. MEDICAL STORES / PHARMACIES
-- ============================================================================

CREATE TABLE IF NOT EXISTS medical_stores (
    store_id VARCHAR(64) PRIMARY KEY,
    owner_uid VARCHAR(128) REFERENCES users(uid) ON DELETE SET NULL,
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
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMPTZ,
    deactivated BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_medical_stores_verified_city ON medical_stores(verified, city);
CREATE INDEX idx_medical_stores_owner ON medical_stores(owner_uid);

-- ============================================================================
-- 5. DIAGNOSTIC LABORATORIES
-- ============================================================================

CREATE TABLE IF NOT EXISTS labs (
    lab_id VARCHAR(64) PRIMARY KEY,
    owner_uid VARCHAR(128) REFERENCES users(uid) ON DELETE SET NULL,
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
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMPTZ,
    deactivated BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_labs_verified_city ON labs(verified, city);
CREATE INDEX idx_labs_owner ON labs(owner_uid);

-- Master Laboratory Test Catalog
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

CREATE INDEX idx_lab_catalog_category ON lab_catalog_tests(category);

-- ============================================================================
-- 6. AMBULANCE SERVICES & DRIVERS
-- ============================================================================

CREATE TABLE IF NOT EXISTS ambulances (
    ambulance_id VARCHAR(64) PRIMARY KEY,
    auth_uid VARCHAR(128) REFERENCES users(uid) ON DELETE SET NULL,
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

CREATE INDEX idx_ambulances_city_available ON ambulances(city, is_available);
CREATE INDEX idx_ambulances_auth_uid ON ambulances(auth_uid);

-- Isolated Ambulance Driver Credentials & Private Settings
CREATE TABLE IF NOT EXISTS ambulance_private_settings (
    ambulance_id VARCHAR(64) PRIMARY KEY REFERENCES ambulances(ambulance_id) ON DELETE CASCADE,
    pin_hash VARCHAR(255) NOT NULL,
    fcm_token TEXT,
    fcm_token_updated_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 7. APPOINTMENTS (In-Clinic & Walk-In)
-- ============================================================================

CREATE TABLE IF NOT EXISTS appointments (
    appointment_id VARCHAR(64) PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE RESTRICT,
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

CREATE INDEX idx_appointments_doctor_date ON appointments(doctor_id, date_time);
CREATE INDEX idx_appointments_patient_date ON appointments(patient_id, date_time);
CREATE INDEX idx_appointments_doctor_status ON appointments(doctor_id, doctor_status);

-- ============================================================================
-- 8. PRESCRIPTIONS & CLINICAL REGIMENS
-- ============================================================================

CREATE TABLE IF NOT EXISTS prescriptions (
    prescription_id VARCHAR(64) PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE RESTRICT,
    appointment_id VARCHAR(64) REFERENCES appointments(appointment_id) ON DELETE SET NULL,
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
    -- Vitals
    blood_pressure VARCHAR(32),
    temperature VARCHAR(32),
    pulse VARCHAR(32),
    spo2 VARCHAR(32),
    weight_kg VARCHAR(32),
    height_cm VARCHAR(32),
    respiratory_rate VARCHAR(32),
    -- Advice
    diet_advice TEXT,
    activity_restrictions TEXT,
    lifestyle_advice TEXT,
    general_advice TEXT,
    follow_up_note TEXT,
    next_visit TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_prescriptions_patient ON prescriptions(patient_id, prescription_date DESC);
CREATE INDEX idx_prescriptions_doctor ON prescriptions(doctor_id, prescription_date DESC);
CREATE INDEX idx_prescriptions_appointment ON prescriptions(appointment_id);

-- Prescription Medication Line Items
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

CREATE INDEX idx_presc_medicines_presc ON prescription_medicines(prescription_id);

-- Prescription Ordered Investigations (Lab / Radiology tests)
CREATE TABLE IF NOT EXISTS prescription_investigations (
    id BIGSERIAL PRIMARY KEY,
    prescription_id VARCHAR(64) NOT NULL REFERENCES prescriptions(prescription_id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(32) NOT NULL CHECK (type IN ('lab', 'radiology', 'custom')),
    group_name VARCHAR(128),
    notes TEXT
);

CREATE INDEX idx_presc_investigations_presc ON prescription_investigations(prescription_id);

-- Prescription Cross-Specialty Referrals
CREATE TABLE IF NOT EXISTS prescription_referrals (
    id BIGSERIAL PRIMARY KEY,
    prescription_id VARCHAR(64) NOT NULL REFERENCES prescriptions(prescription_id) ON DELETE CASCADE,
    to_doctor_id VARCHAR(64) REFERENCES doctors(doctor_id) ON DELETE SET NULL,
    doctor_name VARCHAR(255) NOT NULL,
    specialization VARCHAR(128) NOT NULL,
    reason TEXT,
    sent BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_presc_referrals_presc ON prescription_referrals(prescription_id);

-- ============================================================================
-- 9. PATIENT HEALTH RECORDS (Vault)
-- ============================================================================

CREATE TABLE IF NOT EXISTS health_records (
    record_id VARCHAR(64) PRIMARY KEY,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
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
    file_storage VARCHAR(32) NOT NULL DEFAULT 'none' CHECK (file_storage IN ('none', 'localOnly', 'cloudUploaded')),
    storage_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_health_records_patient ON health_records(patient_id, date DESC);

-- ============================================================================
-- 10. DIAGNOSTIC LAB BOOKINGS & LAB ORDERS
-- ============================================================================

-- Patient-Initiated Lab Bookings & Walk-Ins
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
    report_booking_id VARCHAR(64),
    report_submitted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_lab_bookings_patient ON lab_bookings(patient_id, date_time DESC);
CREATE INDEX idx_lab_bookings_lab ON lab_bookings(lab_id, date_time DESC);
CREATE INDEX idx_lab_bookings_status ON lab_bookings(status);

-- Doctor-Initiated Lab Orders
CREATE TABLE IF NOT EXISTS lab_orders (
    order_id VARCHAR(64) PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE RESTRICT,
    lab_id VARCHAR(64) REFERENCES labs(lab_id) ON DELETE SET NULL,
    appointment_id VARCHAR(64) REFERENCES appointments(appointment_id) ON DELETE SET NULL,
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
    report_submitted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_lab_orders_doctor ON lab_orders(doctor_id);
CREATE INDEX idx_lab_orders_patient ON lab_orders(patient_id);
CREATE INDEX idx_lab_orders_lab ON lab_orders(lab_id);

-- ============================================================================
-- 11. B2B NETWORK CONNECTIONS (Doctors ↔ Pharmacies / Labs)
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

CREATE INDEX idx_pharmacy_conn_doctor ON pharmacy_connections(doctor_id);
CREATE INDEX idx_pharmacy_conn_store ON pharmacy_connections(medical_store_id);

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

CREATE INDEX idx_lab_conn_doctor ON lab_connections(doctor_id);
CREATE INDEX idx_lab_conn_lab ON lab_connections(lab_id);

-- ============================================================================
-- 12. PHARMACY PRESCRIPTION DELIVERIES & DISPENSE TRACKING
-- ============================================================================

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
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_pharmacy_deliv_store ON pharmacy_deliveries(store_id, status);
CREATE INDEX idx_pharmacy_deliv_patient ON pharmacy_deliveries(patient_id);
CREATE INDEX idx_pharmacy_deliv_presc ON pharmacy_deliveries(prescription_id);

CREATE TABLE IF NOT EXISTS pharmacy_delivery_medicines (
    id BIGSERIAL PRIMARY KEY,
    delivery_id VARCHAR(64) NOT NULL REFERENCES pharmacy_deliveries(delivery_id) ON DELETE CASCADE,
    medicine_entry_id VARCHAR(64) NOT NULL,
    availability VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (availability IN ('pending', 'available', 'outOfStock', 'substituted')),
    substitute_name VARCHAR(255)
);

CREATE INDEX idx_pharmacy_deliv_meds ON pharmacy_delivery_medicines(delivery_id);

-- ============================================================================
-- 13. DOCTOR REFERRALS & PERSONAL DIRECTORY
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

CREATE INDEX idx_referrals_from_doc ON referrals(from_doctor_id);
CREATE INDEX idx_referrals_to_doc ON referrals(to_doctor_id);
CREATE INDEX idx_referrals_patient ON referrals(patient_id);

CREATE TABLE IF NOT EXISTS medical_directory (
    entry_id VARCHAR(64) PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(64) NOT NULL,
    phone VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ
);

CREATE INDEX idx_med_directory_doctor ON medical_directory(doctor_id);

-- ============================================================================
-- 14. REVIEWS, PUBLIC PROJECTIONS & HELPFUL VOTES
-- ============================================================================

CREATE TABLE IF NOT EXISTS reviews (
    review_id VARCHAR(128) PRIMARY KEY, -- {patient_id}_{doctor_id}
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

CREATE INDEX idx_reviews_doctor ON reviews(doctor_id);

-- Anonymized Public Review Projection (Stripped of patient identity)
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

CREATE INDEX idx_review_public_doctor ON review_public(doctor_id, rating DESC);

-- Helpful Upvotes for Reviews
CREATE TABLE IF NOT EXISTS review_votes (
    review_id VARCHAR(128) NOT NULL REFERENCES reviews(review_id) ON DELETE CASCADE,
    patient_id VARCHAR(64) NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (review_id, patient_id)
);

-- ============================================================================
-- 15. CUSTOMER SUPPORT & TICKETING
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

CREATE INDEX idx_support_tickets_patient ON support_tickets(patient_id);
CREATE INDEX idx_support_tickets_status ON support_tickets(status);

CREATE TABLE IF NOT EXISTS support_ticket_messages (
    message_id VARCHAR(64) PRIMARY KEY,
    ticket_id VARCHAR(64) NOT NULL REFERENCES support_tickets(ticket_id) ON DELETE CASCADE,
    sender_id VARCHAR(128) NOT NULL,
    sender_name VARCHAR(255) NOT NULL,
    sender_role VARCHAR(32) NOT NULL CHECK (sender_role IN ('patient', 'doctor', 'support')),
    text TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_support_messages_ticket ON support_ticket_messages(ticket_id, created_at ASC);

-- ============================================================================
-- 16. AMBULANCE DISPATCH & EMERGENCY BROADCASTS
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

CREATE INDEX idx_amb_broadcasts_status ON ambulance_broadcasts(status);

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

CREATE INDEX idx_amb_requests_driver ON ambulance_requests(driver_id, status);
CREATE INDEX idx_amb_requests_broadcast ON ambulance_requests(broadcast_id);

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

CREATE INDEX idx_amb_invites_doctor ON ambulance_invites(doctor_id);

-- ============================================================================
-- 17. PROMOTED ADS & SPONSORED CAMPAIGNS
-- ============================================================================

CREATE TABLE IF NOT EXISTS promoted_ads (
    ad_id VARCHAR(64) PRIMARY KEY,
    provider_type VARCHAR(32) NOT NULL CHECK (provider_type IN ('doctor', 'lab', 'pharmacy', 'ambulance')),
    provider_id VARCHAR(64) NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    image_url TEXT NOT NULL,
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

CREATE INDEX idx_promoted_ads_active ON promoted_ads(status, target_city, end_time);
CREATE INDEX idx_promoted_ads_provider ON promoted_ads(provider_id);

-- ============================================================================
-- 18. IN-APP NOTIFICATIONS FEED
-- ============================================================================

CREATE TABLE IF NOT EXISTS in_app_notifications (
    notification_id VARCHAR(64) PRIMARY KEY,
    recipient_uid VARCHAR(128) NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
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

CREATE INDEX idx_notifications_recipient ON in_app_notifications(recipient_uid, is_read, created_at DESC);

-- ============================================================================
-- 19. COMMUNITY CATALOGS (Doctor-Contributed Pharmacopeia & Medical Database)
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

CREATE INDEX idx_comm_medicines_name_lower ON community_medicines(name_lower);

CREATE TABLE IF NOT EXISTS community_diagnoses (
    id VARCHAR(64) PRIMARY KEY,
    text TEXT NOT NULL,
    text_lower TEXT NOT NULL,
    added_by_doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_comm_diagnoses_text_lower ON community_diagnoses(text_lower);

CREATE TABLE IF NOT EXISTS community_lab_tests (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    name_lower VARCHAR(255) NOT NULL,
    group_name VARCHAR(128) NOT NULL,
    added_by_doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_comm_lab_tests_name_lower ON community_lab_tests(name_lower);

CREATE TABLE IF NOT EXISTS community_radiology (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    name_lower VARCHAR(255) NOT NULL,
    group_name VARCHAR(128) NOT NULL,
    added_by_doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_comm_radiology_name_lower ON community_radiology(name_lower);

CREATE TABLE IF NOT EXISTS community_body_parts (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    name_lower VARCHAR(255) NOT NULL,
    added_by_doctor_id VARCHAR(64) NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_comm_body_parts_name_lower ON community_body_parts(name_lower);

-- ============================================================================
-- 20. SYSTEM CONFIGURATION & AUDITING
-- ============================================================================

CREATE TABLE IF NOT EXISTS system_config (
    config_key VARCHAR(64) PRIMARY KEY,
    config_value JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS admin_audit_logs (
    log_id VARCHAR(64) PRIMARY KEY,
    admin_uid VARCHAR(128) NOT NULL,
    admin_email VARCHAR(255) NOT NULL,
    action VARCHAR(64) NOT NULL,
    target_type VARCHAR(64) NOT NULL,
    target_id VARCHAR(64) NOT NULL,
    target_name VARCHAR(255),
    details TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_logs_target ON admin_audit_logs(target_type, target_id);
CREATE INDEX idx_audit_logs_created ON admin_audit_logs(created_at DESC);

CREATE TABLE IF NOT EXISTS security_events (
    event_id VARCHAR(64) PRIMARY KEY,
    severity VARCHAR(16) NOT NULL CHECK (severity IN ('INFO', 'WARNING', 'ERROR', 'CRITICAL')),
    category VARCHAR(32) NOT NULL,
    action VARCHAR(64) NOT NULL,
    uid VARCHAR(128),
    email_hash VARCHAR(64),
    client_ip_hash VARCHAR(64) NOT NULL,
    app_check_present BOOLEAN NOT NULL DEFAULT FALSE,
    method VARCHAR(32),
    pattern VARCHAR(64),
    detail TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_security_events_created ON security_events(created_at DESC);
CREATE INDEX idx_security_events_severity ON security_events(severity);

-- ============================================================================
-- 21. AUTHENTICATION OTP, RATE LIMITING & MAIL QUEUE
-- ============================================================================

CREATE TABLE IF NOT EXISTS otp_challenges (
    challenge_id VARCHAR(128) PRIMARY KEY,
    otp_hash VARCHAR(255) NOT NULL,
    attempts INT NOT NULL DEFAULT 0,
    is_demo BOOLEAN NOT NULL DEFAULT FALSE,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_otp_challenges_expires ON otp_challenges(expires_at);

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

CREATE INDEX idx_otp_sessions_target ON otp_verification_sessions(target, role);

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

CREATE INDEX idx_mail_queue_status ON mail_queue(status, created_at);

-- ============================================================================
-- END OF DATABASE DDL SPECIFICATION
-- ============================================================================
