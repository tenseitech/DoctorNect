-- Defense-in-depth: verified/deactivated admin fields cannot be changed by non-admin clients (raises 42501).

CREATE OR REPLACE FUNCTION private.enforce_verified_admin_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF COALESCE(private.is_super_admin(), FALSE)
       OR current_setting('role', true) = 'service_role'
       OR (auth.jwt() ->> 'role') = 'service_role' THEN
        RETURN NEW;
    END IF;
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME = 'doctors' OR TG_TABLE_NAME = 'labs' OR TG_TABLE_NAME = 'medical_stores' THEN
        IF NEW.verified IS DISTINCT FROM OLD.verified
           OR NEW.deactivated IS DISTINCT FROM OLD.deactivated THEN
            RAISE EXCEPTION 'FORBIDDEN: verification lifecycle is admin-controlled' USING ERRCODE = '42501';
        END IF;
    ELSIF TG_TABLE_NAME = 'ambulances' THEN
        IF NEW.verified IS DISTINCT FROM OLD.verified THEN
            RAISE EXCEPTION 'FORBIDDEN: verification lifecycle is admin-controlled' USING ERRCODE = '42501';
        END IF;
    ELSIF TG_TABLE_NAME = 'patients' THEN
        IF NEW.verified IS DISTINCT FROM OLD.verified THEN
            RAISE EXCEPTION 'FORBIDDEN: verification lifecycle is admin-controlled' USING ERRCODE = '42501';
        END IF;
    ELSIF TG_TABLE_NAME = 'users' THEN
        IF NEW.verified IS DISTINCT FROM OLD.verified
           OR NEW.role IS DISTINCT FROM OLD.role
           OR NEW.deactivated IS DISTINCT FROM OLD.deactivated THEN
            RAISE EXCEPTION 'FORBIDDEN: identity lifecycle is admin-controlled' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enforce_verified_admin_columns() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_doctors_verified_admin ON public.doctors;
CREATE TRIGGER trg_doctors_verified_admin
    BEFORE UPDATE ON public.doctors
    FOR EACH ROW
    EXECUTE FUNCTION private.enforce_verified_admin_columns();

DROP TRIGGER IF EXISTS trg_labs_verified_admin ON public.labs;
CREATE TRIGGER trg_labs_verified_admin
    BEFORE UPDATE ON public.labs
    FOR EACH ROW
    EXECUTE FUNCTION private.enforce_verified_admin_columns();

DROP TRIGGER IF EXISTS trg_medical_stores_verified_admin ON public.medical_stores;
CREATE TRIGGER trg_medical_stores_verified_admin
    BEFORE UPDATE ON public.medical_stores
    FOR EACH ROW
    EXECUTE FUNCTION private.enforce_verified_admin_columns();

DROP TRIGGER IF EXISTS trg_ambulances_verified_admin ON public.ambulances;
CREATE TRIGGER trg_ambulances_verified_admin
    BEFORE UPDATE ON public.ambulances
    FOR EACH ROW
    EXECUTE FUNCTION private.enforce_verified_admin_columns();

DROP TRIGGER IF EXISTS trg_patients_verified_admin ON public.patients;
CREATE TRIGGER trg_patients_verified_admin
    BEFORE UPDATE ON public.patients
    FOR EACH ROW
    EXECUTE FUNCTION private.enforce_verified_admin_columns();