const express = require('express');
const crypto = require('crypto');

const app = express();
app.use(express.json());

const PORT = parseInt(process.env.PORT || '8080', 10);

// Health check
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'gcp-msg91-proxy' });
});

// Outbound Egress IP verification endpoint (protected by proxy key)
app.get('/my-ip', async (req, res) => {
  const clientKey = String(req.headers['x-proxy-key'] || '').trim();
  const serverKey = String(process.env.PROXY_SECRET || '').trim();

  if (!clientKey || !serverKey || clientKey.length !== serverKey.length) {
    return res.status(403).json({ error: 'Unauthorized' });
  }

  try {
    const match = crypto.timingSafeEqual(Buffer.from(clientKey), Buffer.from(serverKey));
    if (!match) return res.status(403).json({ error: 'Unauthorized' });
  } catch (_) {
    return res.status(403).json({ error: 'Unauthorized' });
  }

  try {
    const ipRes = await fetch('https://api.ipify.org?format=json');
    const ipData = await ipRes.json();
    res.status(200).json({ egressIp: ipData.ip });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Forwarding endpoint for MSG91 OTP dispatch
app.post('/otp', async (req, res) => {
  // 1. Authenticate caller via x-proxy-key
  const clientKey = String(req.headers['x-proxy-key'] || '').trim();
  const serverKey = String(process.env.PROXY_SECRET || '').trim();

  if (!clientKey || !serverKey || clientKey.length !== serverKey.length) {
    return res.status(403).json({ error: 'Unauthorized: Invalid proxy key' });
  }

  try {
    const match = crypto.timingSafeEqual(Buffer.from(clientKey), Buffer.from(serverKey));
    if (!match) {
      return res.status(403).json({ error: 'Unauthorized: Invalid proxy key' });
    }
  } catch (_) {
    return res.status(403).json({ error: 'Unauthorized: Invalid proxy key' });
  }

  // 2. Validate parameters
  const { mobile, otp, template_id, sender } = req.body || {};
  if (!mobile || !otp || !template_id) {
    return res.status(400).json({ error: 'Missing required fields: mobile, otp, template_id' });
  }

  const authKey = String(process.env.MSG91_AUTH_KEY || '').trim();
  if (!authKey) {
    console.error('[gcp-msg91-proxy] Missing MSG91_AUTH_KEY secret in environment');
    return res.status(500).json({ error: 'Configuration Error: Missing MSG91 credentials' });
  }

  // 3. Dispatch to MSG91 over VPC Connector (exiting via Cloud NAT static IP)
  const url = new URL('https://control.msg91.com/api/v5/otp');
  url.searchParams.set('template_id', template_id);
  url.searchParams.set('mobile', mobile);
  url.searchParams.set('otp', otp);
  if (sender) {
    url.searchParams.set('sender', sender);
  }

  const maskedMobile = String(mobile).replace(/(\d{2})(\d+)(\d{4})/, '$1******$3');
  console.info(`[gcp-msg91-proxy] Dispatching OTP for ${maskedMobile}`);

  try {
    const msg91Res = await fetch(url.toString(), {
      method: 'POST',
      headers: {
        authkey: authKey,
        'content-type': 'application/json',
        accept: 'application/json',
      },
    });

    const bodyText = await msg91Res.text();
    console.info(`[gcp-msg91-proxy] MSG91 responded HTTP ${msg91Res.status}`);
    res.status(msg91Res.status).send(bodyText);
  } catch (err) {
    console.error('[gcp-msg91-proxy] Network error forwarding to MSG91:', err.message);
    res.status(502).json({ error: 'Bad Gateway: Failed to contact MSG91' });
  }
});

app.listen(PORT, () => {
  console.log(`MSG91 proxy service listening on port ${PORT}`);
});
