{{flutter_js}}
{{flutter_build_config}}

// Load CanvasKit from the app server (not gstatic.com) when CDN is blocked.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});
