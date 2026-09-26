const https = require('https');
const fs = require('fs');
const path = require('path');

// 1. Read functions/.env
const envPath = path.join(__dirname, '..', 'functions', '.env');
const envContent = fs.readFileSync(envPath, 'utf8');
const env = {};
for (const line of envContent.split('\n')) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith('#')) continue;
  const idx = trimmed.indexOf('=');
  if (idx !== -1) {
    env[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim();
  }
}

const authKey = env.MSG91_AUTH_KEY || env.MSG91_AUTHKEY;
const templateId = env.MSG91_TEMPLATE_ID_REGISTRATION || env.MSG91_TEMPLATE_ID;
const senderId = env.MSG91_SENDER_ID || 'DRNECT';

console.log('MSG91 Config:');
console.log('  AuthKey present:', Boolean(authKey), authKey ? authKey.slice(0, 8) + '...' : '');
console.log('  Template ID:', templateId);
console.log('  Sender ID:', senderId);

// Check MSG91 balance / authkey validity
function checkMsg91Balance() {
  return new Promise((resolve) => {
    const options = {
      hostname: 'control.msg91.com',
      path: '/api/v5/widget/getBalance',
      method: 'GET',
      headers: {
        authkey: authKey,
        accept: 'application/json'
      }
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ statusCode: res.statusCode, body: data });
      });
    });
    req.on('error', err => resolve({ error: err.message }));
    req.end();
  });
}

// Check Cloud Run Proxy health
function checkProxyHealth() {
  return new Promise((resolve) => {
    const options = {
      hostname: 'msg91-proxy-658118593597.asia-south1.run.app',
      path: '/health',
      method: 'GET'
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ statusCode: res.statusCode, body: data });
      });
    });
    req.on('error', err => resolve({ error: err.message }));
    req.end();
  });
}

async function run() {
  console.log('\n--- 1. Checking Cloud Run Proxy Health ---');
  const proxyHealth = await checkProxyHealth();
  console.log('Proxy Health Response:', proxyHealth);

  console.log('\n--- 2. Checking MSG91 Direct API AuthKey Status ---');
  const balance = await checkMsg91Balance();
  console.log('MSG91 Balance / AuthKey Response:', balance);
}

run();
