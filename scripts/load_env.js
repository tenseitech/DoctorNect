/**
 * DoctorNect: Secure Environment & Secret Loader
 * 
 * Automatically loads .env.migration and .env from the project root.
 * Guarantees that database credentials and API secrets do NOT need to be
 * passed as inline command-line arguments or shell environment variables.
 */

const fs = require('fs');
const path = require('path');

function parseEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const content = fs.readFileSync(filePath, 'utf8');
  const result = {};
  for (const rawLine of content.split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const eqIdx = line.indexOf('=');
    if (eqIdx === -1) continue;
    const key = line.slice(0, eqIdx).trim();
    let val = line.slice(eqIdx + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    val = val.replace(/\\n/g, '\n');
    result[key] = val;
  }
  return result;
}

function sanitizePostgresUrl(rawUrl) {
  if (!rawUrl || (!rawUrl.startsWith('postgresql://') && !rawUrl.startsWith('postgres://'))) {
    return rawUrl;
  }
  try {
    new URL(rawUrl);
    return rawUrl;
  } catch (e) {
    const protoMatch = rawUrl.match(/^(postgres(?:ql)?:\/\/)(.*)$/);
    if (!protoMatch) return rawUrl;
    const proto = protoMatch[1];
    const rest = protoMatch[2];
    const lastAt = rest.lastIndexOf('@');
    if (lastAt === -1) return rawUrl;
    const authPart = rest.slice(0, lastAt);
    const hostPart = rest.slice(lastAt + 1);
    const colonIdx = authPart.indexOf(':');
    if (colonIdx === -1) return rawUrl;
    const user = authPart.slice(0, colonIdx);
    const pass = authPart.slice(colonIdx + 1);
    const encodedUser = encodeURIComponent(decodeURIComponent(user));
    const encodedPass = encodeURIComponent(decodeURIComponent(pass));
    return `${proto}${encodedUser}:${encodedPass}@${hostPart}`;
  }
}

function adaptToPoolerIfDirect(urlStr) {
  try {
    const u = new URL(urlStr);
    const m = u.hostname.match(/^db\.([a-z0-9]+)\.supabase\.co$/);
    if (m) {
      const projectRef = m[1];
      u.hostname = 'aws-0-ap-south-1.pooler.supabase.com';
      if (!u.username.includes('.')) {
        u.username = `${u.username}.${projectRef}`;
      }
      u.port = '5432';
      return u.toString();
    }
  } catch (e) {}
  return urlStr;
}

function loadEnv() {
  const rootDir = path.resolve(__dirname, '..');
  const candidateFiles = [
    path.join(rootDir, '.env.migration'),
    path.join(__dirname, '.env.migration'),
    path.join(rootDir, '.env'),
    path.join(rootDir, 'functions', '.env'),
  ];

  let loadedFiles = [];

  for (const envPath of candidateFiles) {
    if (fs.existsSync(envPath)) {
      const vars = parseEnvFile(envPath);
      for (const [k, v] of Object.entries(vars)) {
        if (!process.env[k]) {
          process.env[k] = v;
        }
      }
      loadedFiles.push(path.basename(envPath));
    }
  }

  // Auto-discover service-account.json if not explicitly provided
  if (!process.env.FIREBASE_SERVICE_ACCOUNT_PATH && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    const saCandidates = [
      path.join(__dirname, 'service-account.json'),
      path.join(rootDir, 'service-account.json'),
    ];
    for (const sa of saCandidates) {
      if (fs.existsSync(sa)) {
        process.env.FIREBASE_SERVICE_ACCOUNT_PATH = sa;
        process.env.GOOGLE_APPLICATION_CREDENTIALS = sa;
        break;
      }
    }
  }

  // Normalize connection strings & sanitize special characters
  if (!process.env.SUPABASE_DB_URL && process.env.STAGING_SUPABASE_DB_URL) {
    process.env.SUPABASE_DB_URL = process.env.STAGING_SUPABASE_DB_URL;
  }
  if (!process.env.STAGING_SUPABASE_DB_URL && process.env.SUPABASE_DB_URL) {
    process.env.STAGING_SUPABASE_DB_URL = process.env.SUPABASE_DB_URL;
  }

  if (process.env.STAGING_SUPABASE_DB_URL) {
    process.env.STAGING_SUPABASE_DB_URL = adaptToPoolerIfDirect(sanitizePostgresUrl(process.env.STAGING_SUPABASE_DB_URL));
  }
  if (process.env.SUPABASE_DB_URL) {
    process.env.SUPABASE_DB_URL = adaptToPoolerIfDirect(sanitizePostgresUrl(process.env.SUPABASE_DB_URL));
  }
  if (process.env.DATABASE_URL) {
    process.env.DATABASE_URL = adaptToPoolerIfDirect(sanitizePostgresUrl(process.env.DATABASE_URL));
  }

  return loadedFiles;
}

module.exports = { loadEnv, parseEnvFile, sanitizePostgresUrl };
