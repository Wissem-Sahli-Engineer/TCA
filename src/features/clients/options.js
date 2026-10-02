// Pick-lists for client fields. The ids must match backend/models.py
// (VISA_STATUSES, VISA_TYPES, PAYMENT_METHODS, PAYMENT_STATES,
// CLIENT_CATEGORIES); the labels live in src/i18n/translations.js.

export const VISA_STATUSES = [
  { id: "new", tone: "badge-brand", color: "#8B5CF6" },
  { id: "document_review", tone: "badge-warning", color: "#F0924B" },
  { id: "missing_documents", tone: "badge-danger", color: "#ef4444" },
  { id: "ready_for_invitation", tone: "badge-brand", color: "#6366f1" },
  { id: "accepted_in_system", tone: "badge-brand", color: "#3b82f6" },
  { id: "invitation_issued", tone: "badge-brand", color: "#0ea5e9" },
  { id: "client_notified", tone: "badge-brand", color: "#06b6d4" },
  { id: "awaiting_passport", tone: "badge-warning", color: "#f59e0b" },
  { id: "passport_received", tone: "badge-brand", color: "#14b8a6" },
  { id: "file_submitted", tone: "badge-brand", color: "#0d9488" },
  { id: "awaiting_result", tone: "badge-warning", color: "#eab308" },
  { id: "passport_ready", tone: "badge-success", color: "#22c55e" },
  { id: "client_notified_passport_ready", tone: "badge-success", color: "#16a34a" },
  { id: "delivered", tone: "badge-success", color: "#15803d" },
  { id: "closed", tone: "badge-neutral", color: "#9ca3af" },
];

export const MISSING_DOCUMENTS = "missing_documents";

// Visa counts as treated once the passport is ready (or later).
const VISA_TREATED = ["passport_ready", "client_notified_passport_ready", "delivered", "closed"];

// A trip this many days away (or fewer) with an untreated visa is an alert.
export const ALERT_TRIP_DAYS = 10;

export const VISA_TYPES = [
  "pre_entry_swift",
  "government_invitation",
  "first_entry_connect",
  "companion_s1_s2",
  "study_x1_x2",
  "visa_z",
  "other",
];

export const PAYMENT_METHODS = ["cash", "card", "transfer", "cheque"];

export const PAYMENT_STATES = [
  { id: "unpaid", tone: "badge-danger" },
  { id: "partial", tone: "badge-warning" },
  { id: "paid", tone: "badge-success" },
];

export const CLIENT_CATEGORIES = ["normal", "fair", "reservation"];

export const CURRENCIES = ["USD", "EUR", "TND", "LYD"];

// Spellings of the agency's two countries in the free-text passport fields
// (same list as COUNTRY_ALIASES in backend/stats.py).
const COUNTRY_ALIASES = {
  tunisia: ["tunisia", "tunisie", "tunisian", "tunisien", "tunisienne", "tun", "tn", "تونس", "تونسي", "تونسية"],
  libya: ["libya", "libye", "libyan", "libyen", "libyenne", "lby", "ly", "ليبيا", "ليبي", "ليبية"],
};

// "tunisia" | "libya" from the client's passport country (else nationality),
// or null when it's neither.
export function clientCountry(client) {
  for (const value of [client.country, client.nationality]) {
    const v = (value || "").trim().toLowerCase();
    const match = Object.keys(COUNTRY_ALIASES).find((id) => COUNTRY_ALIASES[id].includes(v));
    if (match) return match;
  }
  return null;
}

// A client without a status is treated as a new file.
export const visaStatusOf = (client) => client.visa_status || "new";

export const visaTone = (id) => VISA_STATUSES.find((s) => s.id === id)?.tone || "badge-brand";

export const paymentTone = (id) => PAYMENT_STATES.find((s) => s.id === id)?.tone || "badge-brand";

// Still being worked on: anything past "new" that isn't delivered or closed.
export const isInProgress = (id) => !["new", "delivered", "closed"].includes(id);

function daysUntil(isoDate, today) {
  const [y, m, d] = isoDate.split("-").map(Number);
  const target = Date.UTC(y, m - 1, d);
  const now = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate());
  return Math.round((target - now) / 86400000);
}

// Why a client is in alert (the "Alert" tab and the bell); empty if not:
// - the passport is ready but the client hasn't been told yet;
// - the flight is within ALERT_TRIP_DAYS and the visa isn't treated yet.
export function alertReasons(client, today = new Date()) {
  const reasons = [];
  const status = visaStatusOf(client);
  if (status === "passport_ready") reasons.push({ id: "passportReady" });
  if (client.has_flight && client.flight_date && !VISA_TREATED.includes(status)) {
    const days = daysUntil(client.flight_date, today);
    if (days >= 0 && days <= ALERT_TRIP_DAYS) reasons.push({ id: "tripSoon", date: client.flight_date });
  }
  return reasons;
}

export const isAlert = (client) => alertReasons(client).length > 0;

export const alertText = (t, reason) => t(`alerts.${reason.id}`).replace("{date}", reason.date || "");

// Translated label for a pick-list value, falling back to the raw value
// for anything saved before the list existed.
export function optionLabel(t, namespace, id) {
  if (!id) return "";
  const key = `${namespace}.${id}`;
  const label = t(key);
  return label === key ? id : label;
}
