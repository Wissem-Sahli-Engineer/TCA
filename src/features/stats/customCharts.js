import { optionLabel } from "../clients/options";

// What a custom chart can show — must match SOURCES in backend/stats.py.
// admin: admin-only data; country: the Tunisia/Libya filter applies;
// dated: the "last N months" filter applies.
export const CHART_SOURCES = {
  clients: {
    admin: false,
    country: true,
    dated: true,
    dims: [
      "visa_status", "visa_type", "category", "payment_state", "paiement_type", "currency",
      "nationality", "country", "sex", "destination", "created_by", "month", "flight_month",
    ],
    metrics: ["count", "prix_dossier", "reservation_amount"],
  },
  invoices: {
    admin: true,
    country: true,
    dated: true,
    dims: ["doc_type", "country", "month", "client_name", "company_name", "service_type"],
    metrics: ["count", "amount_paid"],
  },
  treasury: {
    admin: true,
    country: true,
    dated: true,
    dims: ["kind", "country", "month", "product_name", "recorded_by", "counterparty"],
    metrics: ["count", "price"],
  },
  bank_accounts: {
    admin: true,
    country: true,
    dated: false,
    dims: ["name", "country", "currency"],
    metrics: ["count", "balance"],
  },
  payslips: {
    admin: true,
    country: false,
    dated: true,
    dims: ["employee_name", "period_label", "month"],
    metrics: ["count", "net_total", "gross_total", "hours", "advances"],
  },
  employee_requests: {
    admin: false,
    country: false,
    dated: true,
    dims: ["category", "status", "employee_name", "month"],
    metrics: ["count"],
  },
};

export const CHART_TYPES = ["bar", "hbar", "line", "pie"];
export const PERIODS = [3, 6, 12, 24];
export const CHART_COLORS = ["#8B5CF6", "#F0924B", "#22c55e", "#3b82f6", "#ef4444", "#14b8a6", "#eab308", "#ec4899", "#6366f1", "#0ea5e9", "#1F3A5F", "#9ca3af"];

export const sourcesFor = (isAdmin) =>
  Object.keys(CHART_SOURCES).filter((id) => isAdmin || !CHART_SOURCES[id].admin);

const REQUEST_CATEGORIES = { vacations: "requests.vacations", "salary-advances": "requests.salaryAdvances", loans: "requests.loans" };

// Translated label for one group (bar / slice) of a chart.
export function groupLabel(t, source, dim, key) {
  if (key === null || key === undefined || key === "") return t("customCharts.notSet");
  switch (dim) {
    case "visa_status":
      return optionLabel(t, "visa", key);
    case "visa_type":
      return optionLabel(t, "visaType", key);
    case "category":
      return source === "employee_requests"
        ? (REQUEST_CATEGORIES[key] ? t(REQUEST_CATEGORIES[key]) : key)
        : optionLabel(t, "category", key);
    case "payment_state":
      return optionLabel(t, "payment", key);
    case "paiement_type":
      return optionLabel(t, "paymentMethod", key);
    case "currency":
      return optionLabel(t, "currencies", key);
    case "country": {
      const label = optionLabel(t, "countries", key.toLowerCase());
      return label === key.toLowerCase() ? key : label;
    }
    case "doc_type":
      return key === "recu" ? t("invoicesTab.recu") : key === "facture" ? t("invoicesTab.facture") : key;
    case "kind":
      return key === "gathering" ? t("treasuryTab.gathering") : key === "spending" ? t("treasuryTab.spending") : key;
    case "status":
      return optionLabel(t, "status", key);
    default:
      return key;
  }
}

export const periodLabel = (t, months) =>
  months ? t("customCharts.lastMonths").replace("{n}", months) : t("customCharts.allTime");

// The query part of a chart definition, as sent to /api/stats/query.
export const chartQuery = (chart) => ({
  source: chart.source,
  group_by: chart.group_by,
  metric: chart.metric,
  country: chart.country || null,
  months: chart.months || null,
});

export async function fetchChartRows(chart) {
  const res = await fetch("/api/stats/query", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(chartQuery(chart)),
  });
  if (!res.ok) throw new Error("fail");
  return res.json();
}
