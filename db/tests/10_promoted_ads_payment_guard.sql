-- 20261124000001 (+20261125000001): promoted_ads payment/approval columns are server-owned.

SET LOCAL session_replication_role = replica;  -- seed without triggers / FK checks
SELECT tests.seed('public.users', '{"id":"t_doc_uid","firebase_uid":"t_doc_uid","role":"doctor","profile_id":"t_doc_1"}');
SELECT tests.seed('public.users', '{"id":"t_doc2_uid","firebase_uid":"t_doc2_uid","role":"doctor","profile_id":"t_doc_2"}');
SELECT tests.seed('public.promoted_ads', '{"ad_id":"t_ad_live","provider_type":"doctor","provider_id":"t_doc_uid","title":"Live","description":"d","image_url":"https://x/y.png","status":"active","payment_status":"verified","razorpay_order_id":"order_live","razorpay_payment_id":"pay_live","amount_paid":300}');
SELECT tests.seed('public.promoted_ads', '{"ad_id":"t_ad_review","provider_type":"doctor","provider_id":"t_doc_uid","title":"Review","description":"d","image_url":"https://x/y.png","status":"pending_approval","payment_status":"verified","razorpay_order_id":"order_rev","razorpay_payment_id":"pay_rev","amount_paid":300}');
SELECT tests.seed('public.promoted_ads', '{"ad_id":"t_ad_pending","provider_type":"doctor","provider_id":"t_doc_uid","title":"Pending","description":"d","image_url":"https://x/y.png","status":"pending_payment","payment_status":"pending","razorpay_order_id":"order_pend","duration_hours":24}');
SET LOCAL session_replication_role = origin;

-- Owner creates a draft but tries to smuggle paid/live state in: everything server-owned is reset.
SELECT tests.as_user('t_doc_uid');
INSERT INTO public.promoted_ads (ad_id, provider_type, provider_id, title, description, image_url,
                                 status, payment_status, razorpay_order_id, razorpay_payment_id, amount_paid,
                                 start_time, end_time)
VALUES ('t_ad_new', 'doctor', 't_doc_uid', 'New', 'd', 'https://x/y.png',
        'active', 'verified', 'order_fake', 'pay_fake', 999, now(), now() + interval '30 days');
SELECT tests.as_owner();
SELECT tests.check('insert: status forced to draft', (SELECT status FROM public.promoted_ads WHERE ad_id = 't_ad_new') = 'draft');
SELECT tests.check('insert: payment_status forced to pending', (SELECT payment_status FROM public.promoted_ads WHERE ad_id = 't_ad_new') = 'pending');
SELECT tests.check('insert: razorpay ids cleared', (SELECT razorpay_order_id IS NULL AND razorpay_payment_id IS NULL FROM public.promoted_ads WHERE ad_id = 't_ad_new'));
SELECT tests.check('insert: start/end cleared', (SELECT start_time IS NULL AND end_time IS NULL FROM public.promoted_ads WHERE ad_id = 't_ad_new'));
SELECT tests.check('insert: amount_paid not client-controlled', (SELECT amount_paid FROM public.promoted_ads WHERE ad_id = 't_ad_new') = 0);

-- Owner cannot create an ad for another provider.
SELECT tests.as_user('t_doc_uid');
SELECT tests.expect_error('insert for another provider is denied',
  $q$INSERT INTO public.promoted_ads (ad_id, provider_type, provider_id, title, description, image_url)
     VALUES ('t_ad_steal', 'doctor', 't_doc2_uid', 'x', 'd', 'https://x/y.png')$q$);

-- Owner CAN edit a draft's creative.
SELECT tests.check('owner edits draft title',
  tests.affected($q$UPDATE public.promoted_ads SET title = 'Edited', description = 'new' WHERE ad_id = 't_ad_new'$q$) = 1);

-- Owner CANNOT set status / payment_status.
SELECT tests.expect_error('draft -> active denied', $q$UPDATE public.promoted_ads SET status = 'active' WHERE ad_id = 't_ad_new'$q$);
SELECT tests.expect_error('draft -> pending_approval denied', $q$UPDATE public.promoted_ads SET status = 'pending_approval' WHERE ad_id = 't_ad_new'$q$);
SELECT tests.expect_error('payment_status -> verified denied', $q$UPDATE public.promoted_ads SET payment_status = 'verified' WHERE ad_id = 't_ad_new'$q$);
SELECT tests.expect_error('pending_payment -> active denied', $q$UPDATE public.promoted_ads SET status = 'active' WHERE ad_id = 't_ad_pending'$q$);

-- razorpay_* / amount_paid / duration on a pending order are pinned silently.
UPDATE public.promoted_ads
   SET razorpay_order_id = 'order_evil', razorpay_payment_id = 'pay_evil', amount_paid = 1, duration_hours = 720
 WHERE ad_id = 't_ad_pending';
SELECT tests.as_owner();
SELECT tests.check('razorpay_order_id pinned', (SELECT razorpay_order_id FROM public.promoted_ads WHERE ad_id = 't_ad_pending') = 'order_pend');
SELECT tests.check('razorpay_payment_id pinned', (SELECT razorpay_payment_id IS NULL FROM public.promoted_ads WHERE ad_id = 't_ad_pending'));
SELECT tests.check('duration pinned while order is open', (SELECT duration_hours FROM public.promoted_ads WHERE ad_id = 't_ad_pending') = 24);

-- Paid / live ads are frozen for the client.
SELECT tests.as_user('t_doc_uid');
SELECT tests.expect_error('edit live ad denied', $q$UPDATE public.promoted_ads SET title = 'Swap' WHERE ad_id = 't_ad_live'$q$);
SELECT tests.expect_error('edit ad under review denied', $q$UPDATE public.promoted_ads SET image_url = 'https://evil/x.png' WHERE ad_id = 't_ad_review'$q$);
-- Clients have no DELETE grant on promoted_ads (paid ads are an audit/refund trail).
SELECT tests.expect_error('client cannot delete a live ad', $q$DELETE FROM public.promoted_ads WHERE ad_id = 't_ad_live'$q$);
SELECT tests.expect_error('client cannot delete a draft either (no DELETE grant)', $q$DELETE FROM public.promoted_ads WHERE ad_id = 't_ad_new'$q$);

-- Another provider cannot touch the ad at all.
SELECT tests.as_user('t_doc2_uid');
SELECT tests.check('non-owner update affects 0 rows',
  tests.affected($q$UPDATE public.promoted_ads SET title = 'x' WHERE ad_id = 't_ad_pending'$q$) = 0);

-- Payment ledgers are server-written only.
SELECT tests.expect_error('client insert razorpay_orders denied',
  $q$INSERT INTO public.razorpay_orders (order_id, user_uid, ad_id, amount_paise, currency, status) VALUES ('order_x', 't_doc2_uid', 't_ad_pending', 1, 'INR', 'paid')$q$);
SELECT tests.expect_error('client insert razorpay_payments denied',
  $q$INSERT INTO public.razorpay_payments (payment_id, order_id) VALUES ('pay_x', 'order_x')$q$);

-- Service role (Cloud Functions) can activate.
SELECT tests.as_service();
SELECT tests.check('service_role activates paid ad',
  tests.affected($q$UPDATE public.promoted_ads SET status = 'pending_approval', payment_status = 'verified', razorpay_payment_id = 'pay_ok', amount_paid = 300 WHERE ad_id = 't_ad_pending'$q$) = 1);
SELECT tests.as_owner();
SELECT tests.check('activation persisted', (SELECT status = 'pending_approval' AND razorpay_payment_id = 'pay_ok' FROM public.promoted_ads WHERE ad_id = 't_ad_pending'));
