{{flutter_js}}
{{flutter_build_config}}

// Fallback fonts (Roboto, emoji, other scripts) load through this server's
// /gstatic/ route (see Caddyfile) instead of fonts.gstatic.com, so browsers
// never send users' IP addresses to Google.
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: "gstatic/s/",
  },
});
