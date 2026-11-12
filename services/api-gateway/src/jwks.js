'use strict';

const crypto = require('node:crypto');

const GOOGLE_JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

class JwksClient {
  constructor(options = {}) {
    this.jwksUrl = options.jwksUrl || GOOGLE_JWKS_URL;
    this.cacheTtlMs = options.cacheTtlMs || 60 * 60 * 1000; // 1 hour
    this.keyCache = new Map(); // kid -> { keyObject, expiresAt }
    this.lastFetchTime = 0;
    this.mockKeys = null; // Map<kid, KeyObject|PEM|JWK>
  }

  setMockKeys(keysMap) {
    this.mockKeys = keysMap;
  }

  clearCache() {
    this.keyCache.clear();
    this.lastFetchTime = 0;
    this.mockKeys = null;
  }

  async getSigningKey(kid) {
    if (!kid) {
      throw new Error('Missing "kid" in token header.');
    }

    // Test override
    if (this.mockKeys && this.mockKeys.has(kid)) {
      const mockKey = this.mockKeys.get(kid);
      if (typeof mockKey === 'string') {
        return crypto.createPublicKey(mockKey);
      }
      if (mockKey.export) {
        return mockKey;
      }
      return crypto.createPublicKey({ key: mockKey, format: 'jwk' });
    }

    const now = Date.now();
    const cached = this.keyCache.get(kid);
    if (cached && cached.expiresAt > now) {
      return cached.keyObject;
    }

    // Refresh keys from JWKS URL (throttle fetches to at most once every 10s if key is missing)
    if (now - this.lastFetchTime > 10000 || !cached) {
      await this.refreshKeys();
    }

    const fresh = this.keyCache.get(kid);
    if (!fresh) {
      throw new Error(`Unable to find public key for kid="${kid}".`);
    }

    return fresh.keyObject;
  }

  async refreshKeys() {
    this.lastFetchTime = Date.now();
    try {
      const response = await fetch(this.jwksUrl, {
        headers: { 'Accept': 'application/json' },
        signal: AbortSignal.timeout(5000),
      });

      if (!response.ok) {
        throw new Error(`JWKS endpoint returned HTTP ${response.status}`);
      }

      const body = await response.json();
      const keys = body.keys || [];
      const expiresAt = Date.now() + this.cacheTtlMs;

      for (const jwk of keys) {
        if (jwk.kid && jwk.kty === 'RSA') {
          try {
            const keyObject = crypto.createPublicKey({ key: jwk, format: 'jwk' });
            this.keyCache.set(jwk.kid, { keyObject, expiresAt });
          } catch (_) {
            // Ignore malformed individual JWK
          }
        }
      }
    } catch (err) {
      // If network fails but we had cached keys, retain them
      if (this.keyCache.size === 0) {
        throw new Error(`Failed to load JWKS: ${err.message}`);
      }
    }
  }
}

module.exports = {
  JwksClient,
  defaultJwksClient: new JwksClient(),
};
