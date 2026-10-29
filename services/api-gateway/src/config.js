'use strict';

module.exports = {
  port: parseInt(process.env.PORT || '3000', 10),
  host: process.env.HOST || '0.0.0.0',
  postgrestUrl: process.env.PGRST_URL || 'http://127.0.0.1:3001',
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID || 'medibond-45fad',
  postgrestJwtSecret: process.env.PGRST_JWT_SECRET || 'doctornect-secure-postgrest-jwt-secret-min32chars',
  postgrestJwtAud: process.env.PGRST_JWT_AUD || 'authenticated',
  serviceRoleKey: process.env.SERVICE_ROLE_KEY || '',
  anonKey: process.env.ANON_KEY || 'doctornect-anon-public-key',
  maxBodySizeBytes: parseInt(process.env.MAX_BODY_SIZE_BYTES || '5242880', 10), // 5 MB
  rateLimitWindowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '60000', 10), // 1 min
  rateLimitMaxRequests: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '300', 10), // 300 req/min
  failedServiceKeyMaxAttempts: parseInt(process.env.FAILED_SERVICE_KEY_MAX_ATTEMPTS || '5', 10), // 5 failed attempts
  failedServiceKeyWindowMs: parseInt(process.env.FAILED_SERVICE_KEY_WINDOW_MS || '900000', 10), // 15 mins
  // Public endpoints accessible without an authenticated user token
  anonPublicAllowlist: [
    '/rest/v1/doctor_directory',
    '/rest/v1/lab_catalog_tests',
    '/healthz',
  ],
  allowedMethods: [
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'OPTIONS',
    'HEAD',
  ],
  // Tables restricted to embedded relation queries only (cannot be queried directly as top-level endpoints by clients)
  clientEmbedOnlyTables: [
    'pharmacy_delivery_medicines',
    'prescription_investigations',
    'prescription_medicines',
    'prescription_referrals',
  ],
  // Tables directly accessible as top-level endpoints by authenticated clients and public anonymous endpoints
  clientDirectAllowedTables: [
    'ambulance_broadcasts',
    'ambulance_location_updates',
    'ambulance_requests',
    'ambulances',
    'appointments',
    'community_body_parts',
    'community_diagnoses',
    'community_lab_tests',
    'community_medicines',
    'community_radiology',
    'doctor_availability',
    'doctor_blocked_dates',
    'doctor_directory',
    'doctor_directory_updates',
    'doctors',
    'family_members',
    'health_records',
    'in_app_notifications',
    'lab_bookings',
    'lab_catalog_tests',
    'lab_connections',
    'lab_orders',
    'labs',
    'medical_directory',
    'medical_stores',
    'patient_doctor_links',
    'patients',
    'pharmacy_connections',
    'pharmacy_deliveries',
    'prescriptions',
    'promoted_ads',
    'referrals',
    'review_public',
    'review_votes',
    'reviews',
    'support_ticket_messages',
    'support_tickets',
    'system_config',
    'users',
    'user_devices',
  ],
  get clientAllowedTables() {
    return [...this.clientDirectAllowedTables, ...this.clientEmbedOnlyTables];
  },
  // Tables restricted strictly to backend / service_role callers
  serviceRoleOnlyTables: [
    'abuse_rate_limits',
    'admin_audit_logs',
    'admin_users',
    'ambulance_invites',
    'ambulance_locations',
    'ambulance_private_settings',
    'ambulance_trip_contacts',
    'doctor_education',
    'doctor_facilities',
    'doctor_invites',
    'doctor_private',
    'mail_queue',
    'otp_challenges',
    'patient_care_team',
    'pharmacy_doctor_invites',
    'provisioning_errors',
    'razorpay_orders',
    'razorpay_payments',
    'razorpay_webhook_events',
    'security_events',
    'storage_audit_logs',
    'super_admins',
    'sync_dead_letter_queue',
  ],
  get serviceRoleAllowedTables() {
    return [...this.clientAllowedTables, ...this.serviceRoleOnlyTables];
  },
  get allowedTables() {
    return this.serviceRoleAllowedTables;
  },

  // RPCs callable by authenticated clients
  clientAllowedRpcs: [
    'accept_ambulance_request',
    'book_appointment_atomic',
    'cancel_ambulance_broadcast',
    'complete_ambulance_trip',
    'create_prescription_atomic',
    'get_ambulance_trip_location',
    'reschedule_appointment_atomic',
    'update_ambulance_location',
    'update_lab_booking_status',
    'update_lab_order_status',
    'update_pharmacy_delivery_status',
  ],
  // RPCs callable strictly by service_role (in addition to client RPCs)
  serviceRoleOnlyRpcs: [
    'delete_my_account',
  ],
  get serviceRoleAllowedRpcs() {
    return [...this.clientAllowedRpcs, ...this.serviceRoleOnlyRpcs];
  },
  get allowedRpcs() {
    return this.serviceRoleAllowedRpcs;
  },
};
