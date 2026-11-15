'use strict';

/**
 * In-memory Supabase client mock for promoted_ads unit tests (Postgres-only runtime).
 */
function firestoreAdToSupabaseRow(adId, data = {}) {
  return {
    ad_id: data.adId || adId,
    provider_id: data.providerId,
    status: data.status,
    razorpay_order_id: data.razorpayOrderId,
    razorpay_payment_id: data.razorpayPaymentId,
    duration_hours: data.durationHours,
    amount_paid: data.amountPaid,
    payment_status: data.paymentStatus,
    start_time: data.startTime || data.start_time || null,
    end_time: data.endTime || data.end_time || null,
    ...data,
  };
}

function createPromotedAdsSupabaseMock(initial = {}) {
  const ads = new Map();
  const users = new Map();
  const webhookEvents = new Map();
  const payments = new Map();
  const orders = new Map();

  for (const [adId, row] of Object.entries(initial.ads || {})) {
    ads.set(adId, { ...row });
  }
  for (const [uid, row] of Object.entries(initial.users || {})) {
    users.set(uid, { ...row });
  }

  function buildAdsEqResult(col, val) {
    return {
      async maybeSingle() {
        if (col === 'ad_id') {
          const item = ads.get(val);
          return { data: item ? { ...item } : null, error: null };
        }
        return { data: null, error: null };
      },
      then(resolve, reject) {
        try {
          if (col === 'ad_id') {
            const item = ads.get(val);
            resolve({ data: item ? [{ ...item }] : [], error: null });
          } else {
            resolve({ data: [], error: null });
          }
        } catch (err) {
          if (reject) reject(err);
        }
      },
      update(patch) {
        return {
          eq: async (eqCol, eqVal) => {
            if (eqCol === 'ad_id' && ads.has(eqVal)) {
              ads.set(eqVal, { ...ads.get(eqVal), ...patch });
            }
            return { error: null };
          },
        };
      },
    };
  }

  function adsQuery() {
    return {
      select() {
        return {
          eq(col, val) {
            return buildAdsEqResult(col, val);
          },
        };
      },
      update(patch) {
        return {
          eq: async (col, val) => {
            if (col === 'ad_id' && ads.has(val)) {
              ads.set(val, { ...ads.get(val), ...patch });
            }
            return { error: null };
          },
        };
      },
    };
  }

  const client = {
    ads,
    users,
    webhookEvents,
    payments,
    orders,
    seedAd(adId, firestoreShape) {
      ads.set(adId, firestoreAdToSupabaseRow(adId, firestoreShape));
    },
    from(table) {
      if (table === 'promoted_ads') {
        return adsQuery();
      }
      if (table === 'users') {
        const usersSelect = {
          eq: async (col, val) => {
            if (col === 'firebase_uid') {
              const item = users.get(val);
              return { data: item ? [{ ...item }] : [] };
            }
            return { data: [] };
          },
          or: (filter) => ({
            maybeSingle: async () => {
              const match = String(filter || '').match(/firebase_uid\.eq\.([^,\s)]+)/);
              const uid = match ? match[1] : null;
              const item = uid ? users.get(uid) : null;
              return { data: item ? { ...item } : null, error: null };
            },
          }),
          maybeSingle: async () => ({ data: null, error: null }),
        };
        return {
          select: () => usersSelect,
        };
      }
      if (table === 'razorpay_webhook_events') {
        return {
          select: () => ({
            eq: async (col, val) => {
              if (col === 'event_id') {
                const item = webhookEvents.get(val);
                return { data: item ? [{ ...item }] : [] };
              }
              return { data: [] };
            },
          }),
          upsert: async (data) => {
            webhookEvents.set(data.event_id, { ...data });
            return { error: null };
          },
        };
      }
      if (table === 'razorpay_payments') {
        return {
          select: () => ({
            eq: async (col, val) => {
              if (col === 'payment_id') {
                const item = payments.get(val);
                return { data: item ? [{ ...item }] : [] };
              }
              return { data: [] };
            },
          }),
          upsert: async (data) => {
            payments.set(data.payment_id, { ...data });
            return { error: null };
          },
        };
      }
      if (table === 'razorpay_orders') {
        return {
          upsert: async (data) => {
            orders.set(data.order_id, { ...data });
            return { error: null };
          },
        };
      }
      throw new Error(`Unexpected table: ${table}`);
    },
  };

  return client;
}

module.exports = {
  createPromotedAdsSupabaseMock,
  firestoreAdToSupabaseRow,
};