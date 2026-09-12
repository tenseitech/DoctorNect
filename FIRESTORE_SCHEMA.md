# Medibond — Firestore schema (rules ke saath)

Project: `medibond-45fad`

## Auth → `users/{uid}`

| Field | Type | Notes |
|-------|------|--------|
| `role` | string | `"doctor"` \| `"patient"` |
| `doctorId` | string? | e.g. `d1` (doctors only) |
| `patientId` | string? | e.g. `p_<uid>` (patients only) |
| `email` | string? | |
| `phone` | string? | |
| `createdAt` | timestamp | |

Register par document banao; rules `role` change block karti hain.

## Collections

### `doctors/{doctorId}` — patient search

Public read jab `verified == true`. Doctor apni profile update kare.

Maps to: `RegisteredDoctorsStore`, doctor profile screens.

### `patients/{patientId}` — private

Sirf patient read/write. Doctor ko patient info **appointments** se milti hai (denormalized fields).

### `appointments/{appointmentId}`

| Field | Notes |
|-------|--------|
| `appointmentId` | APT… |
| `doctorId` | d1, d2… |
| `patientId` | patient doc id |
| `dateTime` | timestamp |
| `doctorStatus` | confirmed, cancelled… |
| `patientStatus` | confirmed, pending… |
| `tokenNumber`, `slotLabel`, `clinicName`, … | booking flow |

- Patient: create + update (cancel/reschedule)
- Doctor: read + update (status, clinical)

### `prescriptions/{id}`

Doctor create; patient + doctor read.

### `reviews/{id}`

Patient create; sab read; doctor sirf `doctorReply` update.

### `health_records/{id}`, `family_members/{id}`, `lab_bookings/{id}`

Patient-only.

### `doctor_availability/{doctorId}`

Sab read (slots); doctor write.

### `in_app_notifications/{id}`

`recipientUid` = Firebase Auth uid.

## Deploy rules

```powershell
cd C:\Users\Asus\Desktop\doctor
firebase use medibond-45fad
firebase deploy --only firestore
```

Console se bhi: **Firestore → Rules** → `firestore.rules` paste → **Publish**.

## Dev vs production

- **Test mode** (30 days open): sirf development.
- Ye rules **production-style** hain — Auth + role required.

Pehle login wire karo, phir `users/{uid}` create karo registration par.
