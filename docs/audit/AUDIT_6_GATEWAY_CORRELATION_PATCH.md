# Audit 6 — Gateway request correlation (apply with Audit 4 deploy)

`emitAuditLog` and `request_context.js` are ready. **Do not commit** `server.js` while it contains uncommitted Audit 4 `/livez`/`/readyz` work.

When integrating (after Audit 4 hold clears or on a combined deploy branch), add to `services/api-gateway/src/server.js`:

```javascript
const { resolveRequestId, REQUEST_ID_HEADER } = require('./request_context');
```

Inside the request handler:

```javascript
const requestId = resolveRequestId(req);
```

In `sendJson` response headers:

```javascript
[REQUEST_ID_HEADER]: requestId,
```

In `emitAuditLog({ ... requestId })`.