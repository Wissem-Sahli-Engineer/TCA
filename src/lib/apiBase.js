import { Capacitor } from "@capacitor/core";

// The web build calls the backend with relative "/api/..." paths, proxied by
// Vite in dev (see vite.config.js) or by a reverse proxy in production. The
// native iOS app has no such proxy — its assets load from capacitor://localhost,
// so "/api/..." has to be rewritten to the backend's real network address.
//
// TODO before shipping to the App Store: point this at your deployed HTTPS
// backend instead of a LAN IP, and remove the matching ATS exception in
// ios/App/App/Info.plist.
const NATIVE_API_BASE = "http://10.30.30.41:8001";

export const API_BASE = Capacitor.isNativePlatform() ? NATIVE_API_BASE : "";

// Rewrites a same-origin "/api/..." path to the real backend URL when running
// as a native app; a no-op on the web where the proxy already handles it.
export function apiUrl(path) {
  if (!path || !API_BASE || !path.startsWith("/api/")) return path;
  return `${API_BASE}${path.replace(/^\/api/, "")}`;
}
