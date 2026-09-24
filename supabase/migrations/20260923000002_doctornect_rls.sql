-- ============================================================================
-- DOCTORNECT PLATFORM — ROW-LEVEL SECURITY (RLS) & HELPER FUNCTIONS
-- ============================================================================
-- Description: Production RLS policies enforcing strict role-based access,
--               clinical vault confidentiality, doctor verification gating,
--               care-team access checks, and infrastructure table lockdown.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. RLS Helper Functions in PostgreSQL
-- ----------------------------------------------------------------------------
-- Returns the authenticated user's role from public.users
CREATE OR REPLACE FUNCTION current_user_role()
RETURNS TEXT STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT role FROM users WHERE id = auth.uid();
$$ LANGUAGE sql;

-- Returns the authenticated user's domain profile_id (e.g. 'd1', 'p123', 'ms_456')
CREATE OR REPLACE FUNCTION current_profile_id()
RETURNS TEXT STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT profile_id FROM users WHERE id = auth.uid();
$$ LANGUAGE sql;

-- Returns true if user is super admin or in hardcoded admin email allowlist
CREATE OR REPLACE FUNCTION is_super_admin()
RETURNS BOOLEAN STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT (
        current_user_role() IN ('super_admin', 'superAdmin', 'admin')
        OR LOWER(auth.jwt() ->> 'email') IN (
            'sharmasd2@gmail.com',
            'tenseitechpvtltd@gmail.com',
            'admin@doctornect.com',
            'superadmin@doctornect.com',
            'support@doctornect.com'
        )
    );
$$ LANGUAGE sql;

-- Returns true if caller is a Doctor who has passed Stage 2 admin verification
CREATE OR REPLACE FUNCTION is_verified_doctor()
RETURNS BOOLEAN STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM doctors 
        WHERE doctor_id = current_profile_id() 
          AND verified = TRUE 
          AND deactivated = FALSE
    );
$$ LANGUAGE sql;

-- Returns true if user has finished profile onboarding
CREATE OR REPLACE FUNCTION is_profile_completed()
RETURNS BOOLEAN STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT COALESCE(profile_completed, FALSE) FROM users WHERE id = auth.uid();
$$ LANGUAGE sql;

-- Returns true if a verified doctor is authorized to view a patient's clinical vault
CREATE OR REPLACE FUNCTION doctor_can_access_patient(target_patient_id TEXT)
RETURNS BOOLEAN STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM patients p
        WHERE p.patient_id = target_patient_id
          AND p.share_records_with_doctors = TRUE
          AND is_verified_doctor()
          AND (
              p.primary_doctor_id = current_profile_id()
              OR p.invited_doctor_id = current_profile_id()
              OR current_profile_id() = ANY(p.care_team_doctor_ids)
              OR EXISTS (
                  SELECT 1 FROM patient_doctor_links pdl
                  WHERE pdl.patient_id = target_patient_id
                    AND pdl.doctor_id = current_profile_id()
              )
              OR EXISTS (
                  SELECT 1 FROM appointments a
                  WHERE a.patient_id = target_patient_id
                    AND a.doctor_id = current_profile_id()
              )
          )
    );
$$ LANGUAGE sql;

-- ----------------------------------------------------------------------------
-- Table: `facilities`
-- ----------------------------------------------------------------------------
-- Read: Any authenticated user can browse hospitals & clinics
CREATE POLICY "facilities_select_auth" ON facilities
    FOR SELECT TO authenticated USING (TRUE);

-- Write: Super Admin only
CREATE POLICY "facilities_write_admin" ON facilities
    FOR ALL TO authenticated USING (is_super_admin()) WITH CHECK (is_super_admin());

-- ----------------------------------------------------------------------------
-- Table: `users`
-- ----------------------------------------------------------------------------
-- Read: User can view own profile or Super Admin can view all
CREATE POLICY "users_select_owner_or_admin" ON users
    FOR SELECT TO authenticated
    USING (id = auth.uid() OR is_super_admin());

-- Insert: Self-registration or Super Admin
CREATE POLICY "users_insert_self_or_admin" ON users
    FOR INSERT TO authenticated
    WITH CHECK (id = auth.uid() OR is_super_admin());

-- Update: Owner updates profile fields; verified and role changes require Super Admin
CREATE POLICY "users_update_owner_or_admin" ON users
    FOR UPDATE TO authenticated
    USING (id = auth.uid() OR is_super_admin())
    WITH CHECK (
        is_super_admin() 
        OR (
            id = auth.uid() 
            AND role = (SELECT role FROM users WHERE id = auth.uid())
            AND verified = (SELECT verified FROM users WHERE id = auth.uid())
        )
    );

-- Delete: Super Admin only
CREATE POLICY "users_delete_admin" ON users
    FOR DELETE TO authenticated USING (is_super_admin());

-- ----------------------------------------------------------------------------
-- Table: `doctors`
-- ----------------------------------------------------------------------------
-- Read: Verified doctors are discoverable by everyone; doctor can read own unverified profile; Super Admin reads all
CREATE POLICY "doctors_select" ON doctors
    FOR SELECT TO authenticated
    USING (verified = TRUE OR owner_uid = auth.uid() OR is_super_admin());

-- Insert: Owner on registration or Super Admin
CREATE POLICY "doctors_insert" ON doctors
    FOR INSERT TO authenticated
    WITH CHECK ((owner_uid = auth.uid() AND verified = FALSE) OR is_super_admin());

-- Update: Doctor can edit profile info, but cannot alter verified, rating, or review_count
CREATE POLICY "doctors_update" ON doctors
    FOR UPDATE TO authenticated
    USING (owner_uid = auth.uid() OR is_super_admin())
    WITH CHECK (
        is_super_admin()
        OR (
            owner_uid = auth.uid()
            AND verified = (SELECT verified FROM doctors WHERE doctor_id = current_profile_id())
            AND rating = (SELECT rating FROM doctors WHERE doctor_id = current_profile_id())
            AND review_count = (SELECT review_count FROM doctors WHERE doctor_id = current_profile_id())
        )
    );

-- Delete: Super Admin only
CREATE POLICY "doctors_delete" ON doctors
    FOR DELETE TO authenticated USING (is_super_admin());

-- ----------------------------------------------------------------------------
-- Tables: `doctor_education`, `doctor_facilities`
-- ----------------------------------------------------------------------------
-- Read: Publicly readable for doctor profile display
CREATE POLICY "doctor_edu_select" ON doctor_education FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "doctor_fac_select" ON doctor_facilities FOR SELECT TO authenticated USING (TRUE);

-- Write: Owning doctor or Super Admin
CREATE POLICY "doctor_edu_modify" ON doctor_education
    FOR ALL TO authenticated
    USING (doctor_id = current_profile_id() OR is_super_admin())
    WITH CHECK (doctor_id = current_profile_id() OR is_super_admin());

CREATE POLICY "doctor_fac_modify" ON doctor_facilities
    FOR ALL TO authenticated
    USING (doctor_id = current_profile_id() OR is_super_admin())
    WITH CHECK (doctor_id = current_profile_id() OR is_super_admin());

-- ----------------------------------------------------------------------------
-- Tables: `doctor_availability`, `doctor_blocked_dates`
-- ----------------------------------------------------------------------------
-- Read: Public for patient slot booking
CREATE POLICY "doc_avail_select" ON doctor_availability FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "doc_blocked_select" ON doctor_blocked_dates FOR SELECT TO authenticated USING (TRUE);

-- Write: Verified doctor modifies own schedule
CREATE POLICY "doc_avail_write" ON doctor_availability
    FOR ALL TO authenticated
    USING (doctor_id = current_profile_id() AND is_verified_doctor())
    WITH CHECK (doctor_id = current_profile_id() AND is_verified_doctor());

CREATE POLICY "doc_blocked_write" ON doctor_blocked_dates
    FOR ALL TO authenticated
    USING (doctor_id = current_profile_id() AND is_verified_doctor())
    WITH CHECK (doctor_id = current_profile_id() AND is_verified_doctor());

-- ----------------------------------------------------------------------------
-- Table: `patients`
-- ----------------------------------------------------------------------------
-- Read: Patient reads own profile, or authorized doctor on care team, or Super Admin
CREATE POLICY "patients_select" ON patients
    FOR SELECT TO authenticated
    USING (
        owner_uid = auth.uid() 
        OR doctor_can_access_patient(patient_id) 
        OR is_super_admin()
    );

-- Insert: Owning patient on registration
CREATE POLICY "patients_insert" ON patients
    FOR INSERT TO authenticated
    WITH CHECK (owner_uid = auth.uid());

-- Update: Patient updates own profile (verified status is locked)
CREATE POLICY "patients_update" ON patients
    FOR UPDATE TO authenticated
    USING (owner_uid = auth.uid() OR is_super_admin())
    WITH CHECK (
        is_super_admin() 
        OR (owner_uid = auth.uid() AND verified = (SELECT verified FROM patients WHERE patient_id = current_profile_id()))
    );

-- Delete: Forbidden
CREATE POLICY "patients_delete" ON patients FOR DELETE TO authenticated USING (FALSE);

-- ----------------------------------------------------------------------------
-- Table: `patient_care_team` & `patient_doctor_links`
-- ----------------------------------------------------------------------------
-- Read: Patient or linked doctor
CREATE POLICY "care_team_select" ON patient_care_team
    FOR SELECT TO authenticated
    USING (patient_id = current_profile_id() OR doctor_id = current_profile_id());

-- Modify: Patient manages their own care team
CREATE POLICY "care_team_modify" ON patient_care_team
    FOR ALL TO authenticated
    USING (patient_id = current_profile_id())
    WITH CHECK (patient_id = current_profile_id());

-- Doctor links: Read by patient or doctor
CREATE POLICY "doc_links_select" ON patient_doctor_links
    FOR SELECT TO authenticated
    USING (patient_id = current_profile_id() OR doctor_id = current_profile_id());

-- Doctor links insert: Patient booking appointment OR referring doctor sending referral
CREATE POLICY "doc_links_insert" ON patient_doctor_links
    FOR INSERT TO authenticated
    WITH CHECK (
        patient_id = current_profile_id() 
        OR (is_verified_doctor() AND source = 'referral' AND from_doctor_id = current_profile_id())
    );

-- ----------------------------------------------------------------------------
-- Table: `family_members`
-- ----------------------------------------------------------------------------
-- All operations scoped strictly to the managing patient
CREATE POLICY "family_members_owner_only" ON family_members
    FOR ALL TO authenticated
    USING (patient_id = current_profile_id())
    WITH CHECK (patient_id = current_profile_id());

-- ----------------------------------------------------------------------------
-- Table: `medical_stores`
-- ----------------------------------------------------------------------------
-- Read: Verified stores are public; store reads own unverified profile; Super Admin reads all
CREATE POLICY "medical_stores_select" ON medical_stores
    FOR SELECT TO authenticated
    USING (verified = TRUE OR owner_uid = auth.uid() OR is_super_admin());

-- Insert: Owning pharmacist or Super Admin
CREATE POLICY "medical_stores_insert" ON medical_stores
    FOR INSERT TO authenticated
    WITH CHECK ((owner_uid = auth.uid() AND verified = FALSE) OR is_super_admin());

-- Update: Store owner updates business details (verified status is locked)
CREATE POLICY "medical_stores_update" ON medical_stores
    FOR UPDATE TO authenticated
    USING (owner_uid = auth.uid() OR is_super_admin())
    WITH CHECK (
        is_super_admin()
        OR (owner_uid = auth.uid() AND verified = (SELECT verified FROM medical_stores WHERE store_id = current_profile_id()))
    );

-- Delete: Super Admin only
CREATE POLICY "medical_stores_delete" ON medical_stores FOR DELETE TO authenticated USING (is_super_admin());

-- ----------------------------------------------------------------------------
-- Table: `labs` & `lab_catalog_tests`
-- ----------------------------------------------------------------------------
-- Read: Verified labs are public; lab reads own profile; Super Admin reads all
CREATE POLICY "labs_select" ON labs
    FOR SELECT TO authenticated
    USING (verified = TRUE OR owner_uid = auth.uid() OR is_super_admin());

-- Insert: Owning lab operator or Super Admin
CREATE POLICY "labs_insert" ON labs
    FOR INSERT TO authenticated
    WITH CHECK ((owner_uid = auth.uid() AND verified = FALSE) OR is_super_admin());

-- Update: Lab owner updates facility details (verified status is locked)
CREATE POLICY "labs_update" ON labs
    FOR UPDATE TO authenticated
    USING (owner_uid = auth.uid() OR is_super_admin())
    WITH CHECK (
        is_super_admin()
        OR (owner_uid = auth.uid() AND verified = (SELECT verified FROM labs WHERE lab_id = current_profile_id()))
    );

-- Delete: Super Admin only
CREATE POLICY "labs_delete" ON labs FOR DELETE TO authenticated USING (is_super_admin());

-- Lab Catalog: Public read; Super Admin write only
CREATE POLICY "lab_catalog_select" ON lab_catalog_tests FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "lab_catalog_write" ON lab_catalog_tests FOR ALL TO authenticated USING (is_super_admin()) WITH CHECK (is_super_admin());

-- ----------------------------------------------------------------------------
-- Table: `ambulances`
-- ----------------------------------------------------------------------------
-- Read: Available registered ambulances are browseable by patients/doctors; driver reads own profile
CREATE POLICY "ambulances_select" ON ambulances
    FOR SELECT TO authenticated
    USING (
        auth_uid = auth.uid() 
        OR (is_available = TRUE AND verified = TRUE)
        OR is_super_admin()
    );

-- Insert: Driver self-signup or Super Admin
CREATE POLICY "ambulances_insert" ON ambulances
    FOR INSERT TO authenticated
    WITH CHECK (auth_uid = auth.uid() OR is_super_admin());

-- Update: Driver toggles is_available or updates base details; verified and ratings are locked
CREATE POLICY "ambulances_update" ON ambulances
    FOR UPDATE TO authenticated
    USING (auth_uid = auth.uid() OR is_super_admin())
    WITH CHECK (
        is_super_admin()
        OR (
            auth_uid = auth.uid()
            AND verified = (SELECT verified FROM ambulances WHERE ambulance_id = current_profile_id())
            AND total_rating = (SELECT total_rating FROM ambulances WHERE ambulance_id = current_profile_id())
            AND rating_count = (SELECT rating_count FROM ambulances WHERE ambulance_id = current_profile_id())
        )
    );

-- Delete: Super Admin only
CREATE POLICY "ambulances_delete" ON ambulances FOR DELETE TO authenticated USING (is_super_admin());

-- ----------------------------------------------------------------------------
-- Table: `ambulance_private_settings`
-- ----------------------------------------------------------------------------
-- Private Settings (PIN hash, FCM): Strictly owning driver and Super Admin
CREATE POLICY "ambulance_private_settings_policy" ON ambulance_private_settings
    FOR ALL TO authenticated
    USING (ambulance_id = current_profile_id() OR is_super_admin())
    WITH CHECK (ambulance_id = current_profile_id() OR is_super_admin());

-- ----------------------------------------------------------------------------
-- Table: `appointments`
-- ----------------------------------------------------------------------------
-- Read: Patient party or Doctor party
CREATE POLICY "appointments_select" ON appointments
    FOR SELECT TO authenticated
    USING (
        is_super_admin()
        OR (
            is_profile_completed()
            AND (
                patient_id = current_profile_id()
                OR (doctor_id = current_profile_id() AND is_verified_doctor())
            )
        )
    );

-- Insert: Patient booking for self OR Verified Doctor creating a clinic walk-in
CREATE POLICY "appointments_insert" ON appointments
    FOR INSERT TO authenticated
    WITH CHECK (
        (patient_id = current_profile_id() AND source = 'app')
        OR (doctor_id = current_profile_id() AND is_verified_doctor() AND source = 'walkin')
    );

-- Update: Parties can update appointment status/diagnosis; doctor_id and patient_id cannot be swapped
CREATE POLICY "appointments_update" ON appointments
    FOR UPDATE TO authenticated
    USING (
        patient_id = current_profile_id()
        OR (doctor_id = current_profile_id() AND is_verified_doctor())
        OR is_super_admin()
    )
    WITH CHECK (
        patient_id = (SELECT patient_id FROM appointments WHERE appointment_id = appointments.appointment_id)
        AND doctor_id = (SELECT doctor_id FROM appointments WHERE appointment_id = appointments.appointment_id)
    );

-- Delete: Denied
CREATE POLICY "appointments_delete" ON appointments FOR DELETE TO authenticated USING (FALSE);

-- ----------------------------------------------------------------------------
-- Table: `prescriptions` & Line Items
-- ----------------------------------------------------------------------------
-- Prescriptions Read: Treated patient or prescribing doctor
CREATE POLICY "prescriptions_select" ON prescriptions
    FOR SELECT TO authenticated
    USING (
        is_super_admin()
        OR (
            is_profile_completed()
            AND (
                patient_id = current_profile_id()
                OR (doctor_id = current_profile_id() AND is_verified_doctor())
            )
        )
    );

-- Prescriptions Create/Update: Verified prescribing doctor only
CREATE POLICY "prescriptions_write" ON prescriptions
    FOR ALL TO authenticated
    USING (doctor_id = current_profile_id() AND is_verified_doctor())
    WITH CHECK (doctor_id = current_profile_id() AND is_verified_doctor());

-- Line items inherit prescription ownership
CREATE POLICY "presc_meds_policy" ON prescription_medicines
    FOR ALL TO authenticated
    USING (EXISTS (
        SELECT 1 FROM prescriptions p 
        WHERE p.prescription_id = prescription_medicines.prescription_id 
          AND (p.doctor_id = current_profile_id() OR p.patient_id = current_profile_id())
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM prescriptions p 
        WHERE p.prescription_id = prescription_medicines.prescription_id 
          AND p.doctor_id = current_profile_id() AND is_verified_doctor()
    ));

CREATE POLICY "presc_investigations_policy" ON prescription_investigations
    FOR ALL TO authenticated
    USING (EXISTS (
        SELECT 1 FROM prescriptions p 
        WHERE p.prescription_id = prescription_investigations.prescription_id 
          AND (p.doctor_id = current_profile_id() OR p.patient_id = current_profile_id())
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM prescriptions p 
        WHERE p.prescription_id = prescription_investigations.prescription_id 
          AND p.doctor_id = current_profile_id() AND is_verified_doctor()
    ));

CREATE POLICY "presc_referrals_policy" ON prescription_referrals
    FOR ALL TO authenticated
    USING (EXISTS (
        SELECT 1 FROM prescriptions p 
        WHERE p.prescription_id = prescription_referrals.prescription_id 
          AND (p.doctor_id = current_profile_id() OR p.patient_id = current_profile_id())
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM prescriptions p 
        WHERE p.prescription_id = prescription_referrals.prescription_id 
          AND p.doctor_id = current_profile_id() AND is_verified_doctor()
    ));

-- ----------------------------------------------------------------------------
-- Table: `health_records` (Patient Clinical Vault)
-- ----------------------------------------------------------------------------
-- Read: Patient owner or verified doctor with active care-team access
CREATE POLICY "health_records_select" ON health_records
    FOR SELECT TO authenticated
    USING (
        is_super_admin()
        OR (
            is_profile_completed()
            AND (
                patient_id = current_profile_id()
                OR (shared_with_doctors = TRUE AND doctor_can_access_patient(patient_id))
            )
        )
    );

-- Write: Patient owner only
CREATE POLICY "health_records_write" ON health_records
    FOR ALL TO authenticated
    USING (patient_id = current_profile_id())
    WITH CHECK (patient_id = current_profile_id());

-- ----------------------------------------------------------------------------
-- Table: `lab_bookings`
-- ----------------------------------------------------------------------------
-- Read: Patient who booked or Lab assigned
CREATE POLICY "lab_bookings_select" ON lab_bookings
    FOR SELECT TO authenticated
    USING (patient_id = current_profile_id() OR lab_id = current_profile_id());

-- Insert: Patient creates booking OR Lab creates counter walk-in
CREATE POLICY "lab_bookings_insert" ON lab_bookings
    FOR INSERT TO authenticated
    WITH CHECK (
        (patient_id = current_profile_id() AND source = 'app')
        OR (lab_id = current_profile_id() AND source = 'walkin')
    );

-- Update: Patient cancels/reschedules OR Lab submits report file & marks completed
CREATE POLICY "lab_bookings_update" ON lab_bookings
    FOR UPDATE TO authenticated
    USING (patient_id = current_profile_id() OR lab_id = current_profile_id())
    WITH CHECK (patient_id = (SELECT patient_id FROM lab_bookings WHERE booking_id = lab_bookings.booking_id));

-- Delete: Forbidden
CREATE POLICY "lab_bookings_delete" ON lab_bookings FOR DELETE TO authenticated USING (FALSE);

-- ----------------------------------------------------------------------------
-- Table: `lab_orders`
-- ----------------------------------------------------------------------------
-- Read: Prescribing doctor, target lab, or treated patient
CREATE POLICY "lab_orders_select" ON lab_orders
    FOR SELECT TO authenticated
    USING (
        (doctor_id = current_profile_id() AND is_verified_doctor())
        OR lab_id = current_profile_id()
        OR patient_id = current_profile_id()
    );

-- Insert: Verified prescribing doctor only
CREATE POLICY "lab_orders_insert" ON lab_orders
    FOR INSERT TO authenticated
    WITH CHECK (doctor_id = current_profile_id() AND is_verified_doctor());

-- Update: Doctor updates clinical note OR Lab updates report & status
CREATE POLICY "lab_orders_update" ON lab_orders
    FOR UPDATE TO authenticated
    USING (
        (doctor_id = current_profile_id() AND is_verified_doctor())
        OR lab_id = current_profile_id()
    );

-- Delete: Forbidden
CREATE POLICY "lab_orders_delete" ON lab_orders FOR DELETE TO authenticated USING (FALSE);

-- ----------------------------------------------------------------------------
-- Tables: `pharmacy_connections`, `lab_connections`
-- ----------------------------------------------------------------------------
-- Read/Write: Parties of the connection only
CREATE POLICY "pharmacy_conn_policy" ON pharmacy_connections
    FOR ALL TO authenticated
    USING (
        (is_verified_doctor() AND doctor_id = current_profile_id())
        OR medical_store_id = current_profile_id()
    )
    WITH CHECK (
        (is_verified_doctor() AND doctor_id = current_profile_id())
        OR medical_store_id = current_profile_id()
    );

CREATE POLICY "lab_conn_policy" ON lab_connections
    FOR ALL TO authenticated
    USING (
        (is_verified_doctor() AND doctor_id = current_profile_id())
        OR lab_id = current_profile_id()
    )
    WITH CHECK (
        (is_verified_doctor() AND doctor_id = current_profile_id())
        OR lab_id = current_profile_id()
    );

-- ----------------------------------------------------------------------------
-- Table: `pharmacy_deliveries` & Line Items
-- ----------------------------------------------------------------------------
-- Read: Prescribing doctor, target store, or treated patient
CREATE POLICY "pharmacy_deliv_select" ON pharmacy_deliveries
    FOR SELECT TO authenticated
    USING (
        (is_verified_doctor() AND doctor_id = current_profile_id())
        OR store_id = current_profile_id()
        OR patient_id = current_profile_id()
    );

-- Insert: Prescribing verified doctor only
CREATE POLICY "pharmacy_deliv_insert" ON pharmacy_deliveries
    FOR INSERT TO authenticated
    WITH CHECK (is_verified_doctor() AND doctor_id = current_profile_id());

-- Update: Store marks viewed/dispensed OR doctor updates notes
CREATE POLICY "pharmacy_deliv_update" ON pharmacy_deliveries
    FOR UPDATE TO authenticated
    USING (
        (is_verified_doctor() AND doctor_id = current_profile_id())
        OR store_id = current_profile_id()
    );

-- Line items policy
CREATE POLICY "pharmacy_deliv_meds_policy" ON pharmacy_delivery_medicines
    FOR ALL TO authenticated
    USING (EXISTS (
        SELECT 1 FROM pharmacy_deliveries pd 
        WHERE pd.delivery_id = pharmacy_delivery_medicines.delivery_id 
          AND (pd.doctor_id = current_profile_id() OR pd.store_id = current_profile_id() OR pd.patient_id = current_profile_id())
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM pharmacy_deliveries pd 
        WHERE pd.delivery_id = pharmacy_delivery_medicines.delivery_id 
          AND (pd.doctor_id = current_profile_id() OR pd.store_id = current_profile_id())
    ));

-- ----------------------------------------------------------------------------
-- Table: `referrals`
-- ----------------------------------------------------------------------------
-- Read: Referring doctor or receiving doctor
CREATE POLICY "referrals_select" ON referrals
    FOR SELECT TO authenticated
    USING (
        (is_verified_doctor() AND (from_doctor_id = current_profile_id() OR to_doctor_id = current_profile_id()))
        OR is_super_admin()
    );

-- Insert: Verified doctor sending referral
CREATE POLICY "referrals_insert" ON referrals
    FOR INSERT TO authenticated
    WITH CHECK (is_verified_doctor() AND from_doctor_id = current_profile_id());

-- Update: Receiving doctor accepting or completing referral
CREATE POLICY "referrals_update" ON referrals
    FOR UPDATE TO authenticated
    USING (is_verified_doctor() AND to_doctor_id = current_profile_id())
    WITH CHECK (from_doctor_id = (SELECT from_doctor_id FROM referrals WHERE referral_id = referrals.referral_id));

-- ----------------------------------------------------------------------------
-- Table: `medical_directory`
-- ----------------------------------------------------------------------------
-- Doctor's private personal address book
CREATE POLICY "medical_directory_policy" ON medical_directory
    FOR ALL TO authenticated
    USING (doctor_id = current_profile_id() AND is_verified_doctor())
    WITH CHECK (doctor_id = current_profile_id() AND is_verified_doctor());

-- ----------------------------------------------------------------------------
-- Table: `reviews`
-- ----------------------------------------------------------------------------
-- Read: Patient reviewer, reviewed doctor, or Super Admin
CREATE POLICY "reviews_select" ON reviews
    FOR SELECT TO authenticated
    USING (
        patient_id = current_profile_id()
        OR (doctor_id = current_profile_id() AND is_verified_doctor())
        OR is_super_admin()
    );

-- Insert: Patient authoring review (review_id must equal patientId_doctorId)
CREATE POLICY "reviews_insert" ON reviews
    FOR INSERT TO authenticated
    WITH CHECK (
        patient_id = current_profile_id() 
        AND review_id = current_profile_id() || '_' || doctor_id
    );

-- Update: Patient updates comment/rating OR Doctor updates doctor_reply
CREATE POLICY "reviews_update" ON reviews
    FOR UPDATE TO authenticated
    USING (patient_id = current_profile_id() OR doctor_id = current_profile_id())
    WITH CHECK (
        (patient_id = current_profile_id())
        OR (doctor_id = current_profile_id() AND is_verified_doctor())
    );

-- Votes: Patient toggles helpful vote
CREATE POLICY "review_votes_select" ON review_votes FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "review_votes_modify" ON review_votes
    FOR ALL TO authenticated
    USING (patient_id = current_profile_id())
    WITH CHECK (patient_id = current_profile_id());

-- ----------------------------------------------------------------------------
-- Table: `review_public`
-- ----------------------------------------------------------------------------
-- Publicly readable anonymized projection
CREATE POLICY "review_public_select" ON review_public FOR SELECT USING (TRUE);

-- Direct client modifications forbidden (synced by serverless triggers)
CREATE POLICY "review_public_deny_client_write" ON review_public
    FOR ALL TO authenticated USING (FALSE) WITH CHECK (FALSE);

-- ----------------------------------------------------------------------------
-- Tables: `support_tickets`, `support_ticket_messages`
-- ----------------------------------------------------------------------------
-- Read: Ticket author (patient or doctor) or Super Admin
CREATE POLICY "support_tickets_select" ON support_tickets
    FOR SELECT TO authenticated
    USING (
        patient_id = current_profile_id() 
        OR doctor_id = current_profile_id() 
        OR is_super_admin()
    );

-- Insert: Signed-in user creating ticket
CREATE POLICY "support_tickets_insert" ON support_tickets
    FOR INSERT TO authenticated
    WITH CHECK (
        patient_id = current_profile_id() 
        OR doctor_id = current_profile_id()
    );

-- Messages: Thread participants
CREATE POLICY "support_messages_policy" ON support_ticket_messages
    FOR ALL TO authenticated
    USING (EXISTS (
        SELECT 1 FROM support_tickets st 
        WHERE st.ticket_id = support_ticket_messages.ticket_id 
          AND (st.patient_id = current_profile_id() OR st.doctor_id = current_profile_id() OR is_super_admin())
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM support_tickets st 
        WHERE st.ticket_id = support_ticket_messages.ticket_id 
          AND (st.patient_id = current_profile_id() OR st.doctor_id = current_profile_id() OR is_super_admin())
    ));

-- ----------------------------------------------------------------------------
-- Tables: `ambulance_broadcasts`, `ambulance_requests`, `ambulance_invites`
-- ----------------------------------------------------------------------------
-- Broadcast Read: Booker (patient/doctor) or accepted driver
CREATE POLICY "amb_broadcast_select" ON ambulance_broadcasts
    FOR SELECT TO authenticated
    USING (
        patient_id = current_profile_id()
        OR accepted_driver_id = current_profile_id()
        OR is_super_admin()
    );

-- Broadcast Insert: Booker requesting emergency transport
CREATE POLICY "amb_broadcast_insert" ON ambulance_broadcasts
    FOR INSERT TO authenticated
    WITH CHECK (patient_id = current_profile_id() AND status = 'pending');

-- Broadcast Update: Booker cancels OR driver claims ('pending' -> 'accepted')
CREATE POLICY "amb_broadcast_update" ON ambulance_broadcasts
    FOR UPDATE TO authenticated
    USING (
        patient_id = current_profile_id()
        OR accepted_driver_id = current_profile_id()
        OR status = 'pending'
    );

-- Requests Read: Booker or assigned driver
CREATE POLICY "amb_requests_select" ON ambulance_requests
    FOR SELECT TO authenticated
    USING (patient_id = current_profile_id() OR driver_id = current_profile_id());

-- Requests Insert: Booker creating dispatch copies
CREATE POLICY "amb_requests_insert" ON ambulance_requests
    FOR INSERT TO authenticated
    WITH CHECK (patient_id = current_profile_id() AND status = 'pending');

-- Requests Update: Booker or driver updating status
CREATE POLICY "amb_requests_update" ON ambulance_requests
    FOR UPDATE TO authenticated
    USING (patient_id = current_profile_id() OR driver_id = current_profile_id());

-- Invites: Doctor creates; driver claims
CREATE POLICY "amb_invites_policy" ON ambulance_invites
    FOR ALL TO authenticated
    USING (
        (is_verified_doctor() AND doctor_id = current_profile_id())
        OR is_super_admin()
    )
    WITH CHECK (
        (is_verified_doctor() AND doctor_id = current_profile_id())
        OR is_super_admin()
    );

-- ----------------------------------------------------------------------------
-- Table: `promoted_ads`
-- ----------------------------------------------------------------------------
-- Read: Public carousel display
CREATE POLICY "promoted_ads_select" ON promoted_ads FOR SELECT USING (TRUE);

-- Insert: Logged-in provider creating a draft/pending ad
CREATE POLICY "promoted_ads_insert" ON promoted_ads
    FOR INSERT TO authenticated
    WITH CHECK (
        provider_id = (SELECT profile_id FROM users WHERE id = auth.uid())
        AND status IN ('draft', 'pending_payment')
        AND payment_status = 'pending'
    );

-- Update: Sponsoring provider editing draft content OR Super Admin approving
CREATE POLICY "promoted_ads_update" ON promoted_ads
    FOR UPDATE TO authenticated
    USING (
        (provider_id = (SELECT profile_id FROM users WHERE id = auth.uid()) AND status IN ('draft', 'pending_payment'))
        OR is_super_admin()
    );

-- Delete: Provider owner or Super Admin
CREATE POLICY "promoted_ads_delete" ON promoted_ads
    FOR DELETE TO authenticated
    USING (
        provider_id = (SELECT profile_id FROM users WHERE id = auth.uid())
        OR is_super_admin()
    );

-- ----------------------------------------------------------------------------
-- Table: `in_app_notifications`
-- ----------------------------------------------------------------------------
-- Read: Recipient only
CREATE POLICY "notifications_select" ON in_app_notifications
    FOR SELECT TO authenticated
    USING (recipient_uid = auth.uid());

-- Update: Recipient can mark is_read = TRUE
CREATE POLICY "notifications_update" ON in_app_notifications
    FOR UPDATE TO authenticated
    USING (recipient_uid = auth.uid())
    WITH CHECK (recipient_uid = auth.uid());

-- Insert/Delete: Clients forbidden (Backend/Edge Functions only)
CREATE POLICY "notifications_deny_client_insert" ON in_app_notifications
    FOR INSERT TO authenticated WITH CHECK (FALSE);
CREATE POLICY "notifications_deny_client_delete" ON in_app_notifications
    FOR DELETE TO authenticated USING (FALSE);

-- ----------------------------------------------------------------------------
-- Tables: `community_medicines`, `community_diagnoses`, `community_lab_tests`, `community_radiology`, `community_body_parts`
-- ----------------------------------------------------------------------------
-- Read: All authenticated users
CREATE POLICY "comm_med_select" ON community_medicines FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "comm_diag_select" ON community_diagnoses FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "comm_lab_select" ON community_lab_tests FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "comm_rad_select" ON community_radiology FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "comm_body_select" ON community_body_parts FOR SELECT TO authenticated USING (TRUE);

-- Insert: Verified doctors only
CREATE POLICY "comm_med_insert" ON community_medicines FOR INSERT TO authenticated 
    WITH CHECK (is_verified_doctor() AND added_by_doctor_id = current_profile_id());
CREATE POLICY "comm_diag_insert" ON community_diagnoses FOR INSERT TO authenticated 
    WITH CHECK (is_verified_doctor() AND added_by_doctor_id = current_profile_id());
CREATE POLICY "comm_lab_insert" ON community_lab_tests FOR INSERT TO authenticated 
    WITH CHECK (is_verified_doctor() AND added_by_doctor_id = current_profile_id());
CREATE POLICY "comm_rad_insert" ON community_radiology FOR INSERT TO authenticated 
    WITH CHECK (is_verified_doctor() AND added_by_doctor_id = current_profile_id());
CREATE POLICY "comm_body_insert" ON community_body_parts FOR INSERT TO authenticated 
    WITH CHECK (is_verified_doctor() AND added_by_doctor_id = current_profile_id());

-- ----------------------------------------------------------------------------
-- Tables: `security_events`, `abuse_rate_limits`, `otp_challenges`, `otp_verification_sessions`
-- ----------------------------------------------------------------------------
-- Strict Lockdown: Clients have 0 permissions
CREATE POLICY "security_events_deny_all" ON security_events FOR ALL USING (FALSE);
CREATE POLICY "abuse_rate_limits_deny_all" ON abuse_rate_limits FOR ALL USING (FALSE);
CREATE POLICY "otp_challenges_deny_all" ON otp_challenges FOR ALL USING (FALSE);
CREATE POLICY "otp_sessions_deny_all" ON otp_verification_sessions FOR ALL USING (FALSE);

-- ----------------------------------------------------------------------------
-- Table: `admin_audit_logs` (Immutable Write-Once)
-- ----------------------------------------------------------------------------
-- Read/Write: Super Admin only; Updates and Deletes are permanently blocked
CREATE POLICY "audit_logs_select" ON admin_audit_logs FOR SELECT TO authenticated USING (is_super_admin());
CREATE POLICY "audit_logs_insert" ON admin_audit_logs FOR INSERT TO authenticated WITH CHECK (is_super_admin());
CREATE POLICY "audit_logs_deny_update" ON admin_audit_logs FOR UPDATE USING (FALSE);
CREATE POLICY "audit_logs_deny_delete" ON admin_audit_logs FOR DELETE USING (FALSE);

-- ----------------------------------------------------------------------------
-- Table: `system_config`
-- ----------------------------------------------------------------------------
-- Read: Authenticated users can read pricing tiers & feature flags
CREATE POLICY "system_config_select" ON system_config FOR SELECT TO authenticated USING (TRUE);

-- Write: Super Admin only
CREATE POLICY "system_config_write" ON system_config FOR ALL TO authenticated 
    USING (is_super_admin()) WITH CHECK (is_super_admin());

-- ----------------------------------------------------------------------------
-- Table: `mail_queue`
-- ----------------------------------------------------------------------------
-- Super Admin can enqueue; updates and deletes handled by backend worker
CREATE POLICY "mail_queue_select" ON mail_queue FOR SELECT TO authenticated USING (is_super_admin());
CREATE POLICY "mail_queue_insert" ON mail_queue FOR INSERT TO authenticated WITH CHECK (is_super_admin());
CREATE POLICY "mail_queue_deny_client_update" ON mail_queue FOR UPDATE USING (FALSE);
CREATE POLICY "mail_queue_deny_client_delete" ON mail_queue FOR DELETE USING (FALSE);
