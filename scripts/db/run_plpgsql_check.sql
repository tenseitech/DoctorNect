-- Script: scripts/db/run_plpgsql_check.sql
-- Purpose: Static validation of PL/pgSQL functions via plpgsql_check extension.
-- Note: Requires superuser or rds_superuser to create extension plpgsql_check on staging.
-- DO NOT RUN unless Write Gate is open and plpgsql_check is provisioned.

CREATE EXTENSION IF NOT EXISTS plpgsql_check;

-- 1. public.reschedule_appointment_atomic
SELECT * FROM plpgsql_check_function_tb('public.reschedule_appointment_atomic(varchar, timestamptz, varchar)');

-- 2. public.cancel_ambulance_broadcast
SELECT * FROM plpgsql_check_function_tb('public.cancel_ambulance_broadcast(varchar, text)');

-- 3. public.get_ambulance_trip_location
SELECT * FROM plpgsql_check_function_tb('public.get_ambulance_trip_location(varchar)');

-- 4. public.update_ambulance_location
SELECT * FROM plpgsql_check_function_tb('public.update_ambulance_location(varchar, varchar, numeric, numeric, numeric, numeric)');

-- 5. public.complete_ambulance_trip
SELECT * FROM plpgsql_check_function_tb('public.complete_ambulance_trip(varchar, integer, text)');

-- 6. public.accept_ambulance_request
SELECT * FROM plpgsql_check_function_tb('public.accept_ambulance_request(varchar, varchar, varchar)');

-- 7. public.update_lab_booking_status
SELECT * FROM plpgsql_check_function_tb('public.update_lab_booking_status(varchar, varchar)');

-- 8. public.update_lab_order_status
SELECT * FROM plpgsql_check_function_tb('public.update_lab_order_status(varchar, varchar)');

-- 9. public.update_pharmacy_delivery_status
SELECT * FROM plpgsql_check_function_tb('public.update_pharmacy_delivery_status(varchar, varchar, text, jsonb)');

-- 10. public.book_appointment_atomic
SELECT * FROM plpgsql_check_function_tb('public.book_appointment_atomic(varchar, varchar, varchar, varchar, varchar, integer, varchar, timestamptz, varchar, varchar, integer, varchar, text, varchar, varchar)');

-- 11. public.create_prescription_atomic
SELECT * FROM plpgsql_check_function_tb('public.create_prescription_atomic(varchar, varchar, varchar, jsonb, jsonb, jsonb, text, text, text, text, text, text, text, text, numeric, numeric, text, numeric, numeric, numeric, text, varchar, text, text, varchar, text)');

-- 12. public.get_ambulance_trip_contact
SELECT * FROM plpgsql_check_function_tb('public.get_ambulance_trip_contact(varchar)');

-- 13. private.trg_lock_ambulance_broadcast_status
SELECT * FROM plpgsql_check_function_tb('private.trg_lock_ambulance_broadcast_status()');

-- 14. private.trg_users_guard_insert
SELECT * FROM plpgsql_check_function_tb('private.trg_users_guard_insert()');

