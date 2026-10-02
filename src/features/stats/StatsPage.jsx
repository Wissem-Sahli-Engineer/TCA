import { useEffect, useMemo, useRef, useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { PageTitle } from "../../components/ui/Card";
import { BoxSelect } from "../../components/ui/Input";
import { useScrollReveal } from "../../lib/useScrollReveal";
import { useI18n } from "../../store/i18n";
import { VISA_STATUSES, VISA_TYPES, clientCountry, optionLabel, visaStatusOf } from "../clients/options";
import { CustomChartsSection } from "./CustomChartsSection";

// Recharts anchors axis labels for left-to-right text; under dir="rtl" the
// labels slide onto the bars. Keep the chart LTR and mirror it with
// reversed / orientation instead.
const CHART_STYLE = { direction: "ltr" };

const COUNTRIES = ["tunisia", "libya"];

const COUNTRY_COLORS = { tunisia: "#8B5CF6", libya: "#F0924B" };

export function StatsPage() {
  const root = useRef(null);
  useScrollReveal(root);
  const t = useI18n((s) => s.t);
  // Charts are mirrored in Arabic; their text stays LTR-anchored (see CHART_STYLE).
  const isRtl = useI18n((s) => s.isRtl);
  const [clients, setClients] = useState([]);
  const [country, setCountry] = useState("all");
  const [visaType, setVisaType] = useState("all");

  // Accounting data per country, so switching the filter doesn't refetch.
  const [treasury, setTreasury] = useState({});
  const [invoices, setInvoices] = useState({});
  const [accounts, setAccounts] = useState({});
  const [payslips, setPayslips] = useState([]);

  useEffect(() => {
    const json = (url, fallback) =>
      fetch(url)
        .then((r) => (r.ok ? r.json() : fallback))
        .catch(() => fallback);

    json("/api/clients", []).then((data) => setClients(Array.isArray(data) ? data : []));
    json("/api/payroll/payslips", []).then((data) => setPayslips(Array.isArray(data) ? data : []));

    Promise.all(
      COUNTRIES.map(async (c) => [
        c,
        await json(`/api/treasury?country=${c}`, null),
        await json(`/api/invoices?country=${c}`, []),
        await json(`/api/banking/accounts?country=${c}`, []),
      ])
    ).then((results) => {
      setTreasury(Object.fromEntries(results.map(([c, tr]) => [c, tr?.history || []])));
      setInvoices(Object.fromEntries(results.map(([c, , inv]) => [c, inv])));
      setAccounts(Object.fromEntries(results.map(([c, , , acc]) => [c, acc])));
    });
  }, []);

  const selectedCountries = country === "all" ? COUNTRIES : [country];

  const filtered = clients.filter(
    (c) => (country === "all" || clientCountry(c) === country) && (visaType === "all" || c.visa_type === visaType)
  );

  const series = useMemo(() => {
    const byMonth = {};
    filtered.forEach((c) => {
      const month = (c.created_at || "").slice(0, 7);
      if (!month) return;
      byMonth[month] = (byMonth[month] || 0) + 1;
    });
    return Object.keys(byMonth)
      .sort()
      .map((month) => ({ month, count: byMonth[month] }));
  }, [filtered]);

  const statusCounts = VISA_STATUSES.map((s) => ({
    ...s,
    name: optionLabel(t, "visa", s.id),
    value: filtered.filter((c) => visaStatusOf(c) === s.id).length,
  }));

  const byCountry = COUNTRIES.map((c) => ({
    name: t(`countries.${c}`),
    value: filtered.filter((cl) => clientCountry(cl) === c).length,
    color: COUNTRY_COLORS[c],
  })).filter((c) => c.value > 0);

  const treasuryMonthly = useMemo(() => {
    const merged = {};
    selectedCountries.forEach((c) =>
      (treasury[c] || []).forEach((row) => {
        const bucket = merged[row.month] || { month: row.month, gathering: 0, spending: 0 };
        bucket.gathering += row.gathering;
        bucket.spending += row.spending;
        merged[row.month] = bucket;
      })
    );
    return Object.values(merged).sort((a, b) => a.month.localeCompare(b.month)).slice(-6);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [treasury, country]);

  const invoiceList = selectedCountries.flatMap((c) => invoices[c] || []);
  const invoicesByType = [
    { id: "factures", value: invoiceList.filter((i) => i.doc_type === "facture").length, color: "#8B5CF6" },
    { id: "recus", value: invoiceList.filter((i) => i.doc_type === "recu").length, color: "#F0924B" },
  ].map((i) => ({ ...i, name: t(`statsPage.${i.id}`) }));

  const bankAccounts = selectedCountries.flatMap((c) => accounts[c] || []);

  const payrollByPeriod = useMemo(() => {
    const byPeriod = {};
    payslips.forEach((p) => {
      byPeriod[p.period_label] = (byPeriod[p.period_label] || 0) + (p.net_total ?? p.gross_total);
    });
    return Object.entries(byPeriod).map(([period, total]) => ({ period, total }));
  }, [payslips]);

  const countryName = country === "all" ? t("common.allCountries") : t(`countries.${country}`);

  return (
    <div ref={root} className="page-container-max">
      <PageTitle kicker={t("statsPage.kicker")} title={t("statsPage.title")} />

      <div className="grid-12" style={{ marginBottom: "24px" }}>
        <aside data-reveal className="col-4 card" style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          <p style={{ fontSize: "14px", fontWeight: "700", color: "var(--color-ink)" }}>{t("statsPage.filters")}</p>
          <div>
            <p style={{ marginBottom: "6px", fontSize: "12px", color: "var(--color-muted)" }}>{t("statsPage.country")}</p>
            <BoxSelect value={country} onChange={(e) => setCountry(e.target.value)}>
              <option value="all">{t("common.allCountries")}</option>
              {COUNTRIES.map((c) => (
                <option key={c} value={c}>{t(`countries.${c}`)}</option>
              ))}
            </BoxSelect>
          </div>
          <div>
            <p style={{ marginBottom: "6px", fontSize: "12px", color: "var(--color-muted)" }}>{t("statsPage.visaType")}</p>
            <BoxSelect value={visaType} onChange={(e) => setVisaType(e.target.value)}>
              <option value="all">{t("common.allTypes")}</option>
              {VISA_TYPES.map((v) => (
                <option key={v} value={v}>{optionLabel(t, "visaType", v)}</option>
              ))}
            </BoxSelect>
          </div>
          <p style={{ paddingTop: "8px", fontSize: "12.5px", lineHeight: "1.5", color: "var(--color-muted)" }}>
            {filtered.length} {t("statsPage.clientsMatch")}
          </p>
        </aside>

        <div data-reveal className="col-8 card">
          <h2 style={{ marginBottom: "4px", fontSize: "16px", fontWeight: "700", color: "var(--color-ink)" }}>
            {t("statsPage.newClientsPerMonth")}
          </h2>
          <p style={{ marginBottom: "24px", fontSize: "13px", color: "var(--color-muted)" }}>
            {countryName} · {visaType === "all" ? t("statsPage.allVisaTypes") : optionLabel(t, "visaType", visaType)}
          </p>
          <div style={{ height: "280px" }}>
            {series.length === 0 ? (
              <div className="flex-center" style={{ height: "100%", color: "var(--color-muted)", fontSize: "13px" }}>
                {t("statsPage.noClientData")}
              </div>
            ) : (
              <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
                <LineChart data={series}>
                  <CartesianGrid stroke="var(--color-line)" vertical={false} />
                  <XAxis reversed={isRtl} dataKey="month" tick={{ fill: "#8a8a8f", fontSize: 12 }} axisLine={false} tickLine={false} />
                  <YAxis orientation={isRtl ? "right" : "left"} allowDecimals={false} tick={{ fill: "#8a8a8f", fontSize: 12 }} axisLine={false} tickLine={false} />
                  <Tooltip />
                  <Line type="monotone" dataKey="count" name={t("statsPage.newClients")} stroke="#8B5CF6" strokeWidth={2.4} dot={{ r: 4, fill: "#8B5CF6" }} />
                </LineChart>
              </ResponsiveContainer>
            )}
          </div>
        </div>
      </div>

      <div className="grid-12" style={{ marginBottom: "24px" }}>
        <div data-reveal className="col-6 card">
          <h2 style={{ marginBottom: "16px", fontSize: "16px", fontWeight: "700", color: "var(--color-ink)" }}>
            {t("statsPage.visaStatusChart")}
          </h2>
          <div style={{ height: "400px" }}>
            <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
              <BarChart data={statusCounts} layout="vertical" margin={{ left: 8, right: 8 }}>
                <XAxis reversed={isRtl} type="number" hide allowDecimals={false} />
                <YAxis orientation={isRtl ? "right" : "left"} type="category" dataKey="name" width={170} interval={0} tick={{ fill: "var(--color-ink)", fontSize: 11 }} axisLine={false} tickLine={false} />
                <Tooltip />
                <Bar dataKey="value" radius={isRtl ? [8, 0, 0, 8] : [0, 8, 8, 0]} barSize={14}>
                  {statusCounts.map((s) => (
                    <Cell key={s.name} fill={s.color} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div data-reveal className="col-3 card">
          <h2 style={{ marginBottom: "16px", fontSize: "16px", fontWeight: "700", color: "var(--color-ink)" }}>
            {t("statsPage.byCountry")}
          </h2>
          <div style={{ height: "220px" }}>
            {byCountry.length === 0 ? (
              <div className="flex-center" style={{ height: "100%", color: "var(--color-muted)", fontSize: "13px" }}>{t("statsPage.noDataYet")}</div>
            ) : (
              <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
                <PieChart>
                  <Pie data={byCountry} dataKey="value" nameKey="name" innerRadius={45} outerRadius={75}>
                    {byCountry.map((c) => (
                      <Cell key={c.name} fill={c.color} />
                    ))}
                  </Pie>
                  <Tooltip />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            )}
          </div>
        </div>

        <div data-reveal className="col-3 card">
          <h2 style={{ marginBottom: "16px", fontSize: "16px", fontWeight: "700", color: "var(--color-ink)" }}>
            {t("statsPage.facturesVsRecus")}
          </h2>
          <div style={{ height: "220px" }}>
            {invoicesByType.every((i) => i.value === 0) ? (
              <div className="flex-center" style={{ height: "100%", color: "var(--color-muted)", fontSize: "13px" }}>{t("statsPage.noInvoicesYet")}</div>
            ) : (
              <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
                <PieChart>
                  <Pie data={invoicesByType} dataKey="value" nameKey="name" innerRadius={45} outerRadius={75}>
                    {invoicesByType.map((i) => (
                      <Cell key={i.name} fill={i.color} />
                    ))}
                  </Pie>
                  <Tooltip />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            )}
          </div>
        </div>
      </div>

      <div className="grid-12">
        <div data-reveal className="col-6 card">
          <h2 style={{ marginBottom: "16px", fontSize: "16px", fontWeight: "700", color: "var(--color-ink)" }}>
            {t("statsPage.treasuryChart")}
          </h2>
          <div style={{ height: "240px" }}>
            {treasuryMonthly.length === 0 ? (
              <div className="flex-center" style={{ height: "100%", color: "var(--color-muted)", fontSize: "13px" }}>{t("statsTab.noHistory")}</div>
            ) : (
              <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
                <BarChart data={treasuryMonthly}>
                  <CartesianGrid stroke="var(--color-line)" strokeDasharray="3 3" vertical={false} />
                  <XAxis reversed={isRtl} dataKey="month" tick={{ fill: "#8a8a8f", fontSize: 12 }} axisLine={false} tickLine={false} />
                  <YAxis orientation={isRtl ? "right" : "left"} tick={{ fill: "#8a8a8f", fontSize: 12 }} axisLine={false} tickLine={false} />
                  <Tooltip />
                  <Legend />
                  <Bar dataKey="gathering" name={t("dashboard.gathering")} fill="#8B5CF6" radius={[6, 6, 0, 0]} />
                  <Bar dataKey="spending" name={t("dashboard.spending")} fill="#F0924B" radius={[6, 6, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>
        </div>

        <div data-reveal className="col-3 card">
          <h2 style={{ marginBottom: "16px", fontSize: "16px", fontWeight: "700", color: "var(--color-ink)" }}>
            {t("statsPage.bankBalances")}
          </h2>
          <div style={{ height: "240px" }}>
            {bankAccounts.length === 0 ? (
              <div className="flex-center" style={{ height: "100%", color: "var(--color-muted)", fontSize: "13px" }}>{t("statsPage.noAccountsYet")}</div>
            ) : (
              <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
                <BarChart data={bankAccounts} layout="vertical" margin={{ left: 8, right: 8 }}>
                  <XAxis reversed={isRtl} type="number" hide />
                  <YAxis orientation={isRtl ? "right" : "left"} type="category" dataKey="name" width={90} tick={{ fill: "var(--color-ink)", fontSize: 11 }} axisLine={false} tickLine={false} />
                  <Tooltip />
                  <Bar dataKey="balance" name={t("bankingTab.amountCol")} fill="#22c55e" radius={isRtl ? [6, 0, 0, 6] : [0, 6, 6, 0]} barSize={14} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>
        </div>

        <div data-reveal className="col-3 card">
          <h2 style={{ marginBottom: "16px", fontSize: "16px", fontWeight: "700", color: "var(--color-ink)" }}>
            {t("statsPage.payrollCost")}
          </h2>
          <div style={{ height: "240px" }}>
            {payrollByPeriod.length === 0 ? (
              <div className="flex-center" style={{ height: "100%", color: "var(--color-muted)", fontSize: "13px" }}>{t("statsPage.noPayslipsYet")}</div>
            ) : (
              <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
                <BarChart data={payrollByPeriod}>
                  <XAxis reversed={isRtl} dataKey="period" tick={{ fill: "#8a8a8f", fontSize: 10 }} axisLine={false} tickLine={false} />
                  <YAxis orientation={isRtl ? "right" : "left"} tick={{ fill: "#8a8a8f", fontSize: 12 }} axisLine={false} tickLine={false} />
                  <Tooltip />
                  <Bar dataKey="total" name={t("payroll.grossTotalCol")} fill="#1F3A5F" radius={[6, 6, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>
        </div>
      </div>

      <CustomChartsSection />
    </div>
  );
}
