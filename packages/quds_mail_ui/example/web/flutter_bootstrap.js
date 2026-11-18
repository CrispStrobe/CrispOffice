{{flutter_js}}
{{flutter_build_config}}

// Host assets stay on this origin. Build with --no-web-resources-cdn to bundle
// CanvasKit and the default font. Hosts must bundle/cache any additional fonts
// needed by their content and qualify the resulting application offline.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
    fontFallbackBaseUrl: 'assets/fonts/fallback/',
  },
});
