import { useEffect, useRef, useState } from "react";
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { PageTitle } from "../../components/ui/Card";
import { useScrollReveal } from "../../lib/useScrollReveal";
import { useI18n } from "../../store/i18n";
import { MISSING_DOCUMENTS, VISA_STATUSES, isInProgress, optionLabel } from "../clients/options";

// Recharts anchors axis labels for left-to-right text; under dir="rtl" the
// labels slide onto the bars. Keep the chart LTR and mirror it with
// reversed / orientation instead.
const CHART_STYLE = { direction: "ltr" };

const COUNTRIES = ["tunisia", "libya"];

function Tip({ active, payload, label }) {
  if (!active || !payload?.length) return null;
  return (
    <div
      style={{
        borderRadius: "var(--radius-field)",
        border: "1px solid var(--color-line)",
        backgroundColor: "var(--color-white)",
        padding: "8px 12px",
        fontSize: "12px",
        color: "var(--color-ink)",
        boxShadow: "var(--shadow-soft)",
      }}
    >
      <p style={{ marginBottom: "4px", fontWeight: "600" }}>{label}</p>
      {payload.map((p) => (
        <p key={p.dataKey} style={{ color: "var(--color-muted)" }}>
          {p.name}: {p.value}
        </p>
      ))}
    </div>
  );
}

export function DashboardPage() {
  const root = useRef(null);
  useScrollReveal(root);
  const t = useI18n((s) => s.t);
  // Charts are mirrored in Arabic; their text stays LTR-anchored (see CHART_STYLE).
  const isRtl = useI18n((s) => s.isRtl);

  // Counts come from the server (/clients/summary) — no client list is downloaded.
  const [summary, setSummary] = useState({ total: 0, by_status: {}, alerts: 0 });
  const [treasuryMonthly, setTreasuryMonthly] = useState([]);
  const [monthNet, setMonthNet] = useState(0);
  const [bankTotal, setBankTotal] = useState(0);
  const [invoiceCount, setInvoiceCount] = useState(0);

  useEffect(() => {
    fetch("/api/clients/summary")
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => data && setSummary(data))
      .catch(() => {});

    Promise.all(COUNTRIES.map((c) => fetch(`/api/treasury?country=${c}`).then((r) => (r.ok ? r.json() : null))))
      .then((results) => {
        const merged = {};
        let net = 0;
        results.forEach((data) => {
          if (!data) return;
          net += data.current_month?.net || 0;
          (data.history || []).forEach((row) => {
            const bucket = merged[row.month] || { month: row.month, gathering: 0, spending: 0 };
            bucket.gathering += row.gathering;
            bucket.spending += row.spending;
            merged[row.month] = bucket;
          });
        });
        setMonthNet(net);
        setTreasuryMonthly(Object.values(merged).sort((a, b) => a.month.localeCompare(b.month)).slice(-6));
      })
      .catch(() => {});

    Promise.all(COUNTRIES.map((c) => fetch(`/api/banking/accounts?country=${c}`).then((r) => (r.ok ? r.json() : []))))
      .then((results) => setBankTotal(results.flat().reduce((acc, a) => acc + a.balance, 0)))
      .catch(() => {});

    // One row is enough: the total is in the X-Total-Count header.
    Promise.all(
      COUNTRIES.map((c) =>
        fetch(`/api/invoices?country=${c}&limit=1`).then((r) => (r.ok ? Number(r.headers.get("X-Total-Count") || 0) : 0))
      )
    )
      .then((counts) => setInvoiceCount(counts.reduce((a, b) => a + b, 0)))
      .catch(() => {});
  }, []);

  const statusCounts = VISA_STATUSES.map((s) => ({
    ...s,
    name: optionLabel(t, "visa", s.id),
    value: summary.by_status[s.id] || 0,
  }));
  const missingCount = summary.by_status[MISSING_DOCUMENTS] || 0;
  const alertCount = summary.alerts;
  const inProgress = Object.entries(summary.by_status)
    .filter(([status]) => isInProgress(status))
    .reduce((acc, [, n]) => acc + n, 0);

  const stats = [
    { label: t("dashboard.totalClients"), value: summary.total, note: t("dashboard.inDatabase"), accent: "#8B5CF6" },
    { label: t("dashboard.inProgress"), value: inProgress, note: t("dashboard.awaitingDecision"), accent: "#F0924B" },
    { label: t("dashboard.missingDocs"), value: missingCount, note: t("dashboard.needFollowUp"), accent: "#ef4444" },
    { label: t("dashboard.invoicesReceipts"), value: invoiceCount, note: t("dashboard.issuedToDate"), accent: "#22c55e" },
  ];

  return (
    <div ref={root} className="page-container-max">
      <PageTitle kicker={t("dashboard.kicker")} title={t("dashboard.title")} />

      <div className="grid-12">
        <div data-reveal className="col-7 card-ink">
          <p style={{ fontSize: "12px", fontWeight: "600", textTransform: "uppercase", letterSpacing: "0.14em", color: "rgba(255,255,255,0.5)" }}>
            {t("dashboard.treasuryNet")}
          </p>
          <p style={{ marginTop: "8px", fontSize: "var(--text-hero)", fontWeight: "700", lineHeight: "1" }}>
            {monthNet.toLocaleString()}
          </p>
          <p style={{ marginTop: "12px", maxWidth: "420px", fontSize: "14px", color: "rgba(255,255,255,0.6)" }}>
            {t("dashboard.treasuryNetBody").replace("{amount}", bankTotal.toLocaleString())}
          </p>
        </div>

        <div className="col-5">
          <div className="grid-2">
            {stats.map((s) => (
              <div data-reveal key={s.label} className="stat-mini-card">
                <div className="stat-accent-bar" style={{ background: s.accent }} />
                <p className="stat-label">{s.label}</p>
                <p className="stat-value">{s.value}</p>
                <p className="stat-note">{s.note}</p>
              </div>
            ))}
          </div>
        </div>

        <div data-reveal className="col-8 chart-card">
          <div className="chart-header">
            <h2 style={{ fontSize: "16px", fontWeight: "700", color: "var(--color-ink)" }}>
              {t("dashboard.treasuryChart")}
            </h2>
            <span style={{ fontSize: "12px", color: "var(--color-muted)" }}>{t("dashboard.last6Months")}</span>
          </div>
          <div style={{ height: "280px" }}>
            <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
              <AreaChart data={treasuryMonthly}>
                <CartesianGrid stroke="var(--color-line)" vertical={false} />
                <XAxis reversed={isRtl} dataKey="month" tick={{ fill: "#8a8a8f", fontSize: 12 }} axisLine={false} tickLine={false} />
                <YAxis orientation={isRtl ? "right" : "left"} tick={{ fill: "#8a8a8f", fontSize: 12 }} axisLine={false} tickLine={false} />
                <Tooltip content={<Tip />} />
                <Area type="monotone" dataKey="gathering" name={t("dashboard.gathering")} stroke="#8B5CF6" fill="#ede9fe" strokeWidth={2} />
                <Area type="monotone" dataKey="spending" name={t("dashboard.spending")} stroke="#F0924B" fill="transparent" strokeWidth={2} />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div data-reveal className="col-4 chart-card">
          <h2 style={{ marginBottom: "16px", fontSize: "16px", fontWeight: "700", color: "var(--color-ink)" }}>
            {t("dashboard.byVisaStatus")}
          </h2>
          <div style={{ height: "380px" }}>
            <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
              <BarChart data={statusCounts} layout="vertical" margin={{ left: 8, right: 8 }}>
                <XAxis reversed={isRtl} type="number" hide allowDecimals={false} />
                <YAxis orientation={isRtl ? "right" : "left"} type="category" dataKey="name" width={150} interval={0} tick={{ fill: "var(--color-ink)", fontSize: 11 }} axisLine={false} tickLine={false} />
                <Tooltip content={<Tip />} cursor={{ fill: "var(--color-surface)" }} />
                <Bar dataKey="value" radius={isRtl ? [8, 0, 0, 8] : [0, 8, 8, 0]} barSize={12}>
                  {statusCounts.map((s) => (
                    <Cell key={s.name} fill={s.color} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
          <p style={{ marginTop: "12px", fontSize: "12.5px", color: "var(--color-muted)" }}>
            {alertCount} {t("dashboard.needAlertFollowUp")}
          </p>
        </div>
      </div>
    </div>
  );
}
