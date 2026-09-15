/** Preload Firebase JS SDK modules before FlutterFire init (avoids inline script CSP violations). */
window.__firebaseSdkReady = (async function loadFirebaseSdks() {
  var version = window.flutterfire_web_sdk_version || '12.18.0';
  var base = 'https://www.gstatic.com/firebasejs/' + version + '/';

  window.firebase_core = await import(base + 'firebase-app.js');

  var modules = await Promise.all([
    import(base + 'firebase-auth.js'),
    import(base + 'firebase-firestore-pipelines.js'),
    import(base + 'firebase-functions.js'),
    import(base + 'firebase-storage.js'),
    import(base + 'firebase-messaging.js'),
    import(base + 'firebase-app-check.js'),
  ]);

  window.firebase_auth = modules[0];
  window.firebase_firestore = modules[1];
  window.firebase_functions = modules[2];
  window.firebase_storage = modules[3];
  window.firebase_messaging = modules[4];
  window.firebase_app_check = modules[5];
})();
