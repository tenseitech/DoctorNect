'use strict';

const fs = require('fs');
const path = require('path');

const INDEX = path.resolve(__dirname, '../../backend/functions/index.js');

function removeRange(arr, start1, end1) {
  return [...arr.slice(0, start1 - 1), ...arr.slice(end1)];
}

let lines = fs.readFileSync(INDEX, 'utf8').split('\n');
lines = removeRange(lines, 2082, 2257);
lines = removeRange(lines, 1929, 1982);
lines = removeRange(lines, 1781, 1842);
lines = removeRange(lines, 378, 949);

let text = lines.join('\n');

if (!text.includes("require('./supabase_database_webhook')")) {
  text = text.replace(
    "const crypto = require('crypto');",
    "const crypto = require('crypto');\nconst { supabaseDatabaseWebhookHandler } = require('./supabase_database_webhook');",
  );
}

text = text.replace(
  /\/\*\*[\s\S]*?HTTPS webhook endpoint receiving database events from Supabase\.[\s\S]*?async function supabaseDatabaseWebhookHandler[\s\S]*?\n\}\n\n\/\*\*\n \* HTTPS webhook endpoint receiving database events from Supabase\./,
  '/**\n * HTTPS webhook endpoint receiving database events from Supabase.',
);

fs.writeFileSync(INDEX, text, 'utf8');
console.log('Stripped Firestore triggers from index.js');
