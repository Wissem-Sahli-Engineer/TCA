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
import { VISA_STATUSES, optionLabel, visaStatusOf } from "../clients/options";

const COUNTRIES = ["tunisia", "libya"];

const COUNTRY_COLORS = { tunisia: "#8B5CF6", libya: "#F0924B" };

export function StatsPage() {
  const root = useRef(null);
  useScrollReveal(root);
  const t = useI18n((s) => s.t);
  const [clients, setClients] = useState([]);
  const [country, setCountry] = useState("all");
  const [visaType, setVisaType] = useState("all");

  const [treasuryMonthly, setTreasuryMonthly] = useState([]);
  const [invoicesByType, setInvoicesByType] = useState([]);
  const [bankAccounts, setBankAccounts] = useState([]);
  const [payrollByPeriod, setPayrollByPeriod] = useState([]);

  useEffect(() => {
    fetch("/api/clients")
      .then((r) => (r.ok ? r.json() : []))
      .then((data) => setClients(Array.isArray(data) ? data : []))
      .catch(() => setClients([]));

    Promise.all(COUNTRIES.map((c) => fetch(`/api/treasury?country=${c}`).then((r) => (r.ok ? r.json() : null))))
      .then((results) => {
        const merged = {};
        results.forEach((data) => {
          if (!data) return;
          (data.history || []).forEach((row) => {
            const bucket = merged[row.month] || { month: row.month, gathering: 0, spending: 0 };
            bucket.gathering += row.gathering;
            bucket.spending += row.spending;
            merged[row.month] = bucket;
          });
        });
        setTreasuryMonthly(Object.values(merged).sort((a, b) => a.month.localeCompare(b.month)).slice(-6));
      })
      .catch(() => {});

    Promise.all(COUNTRIES.map((c) => fetch(`/api/invoices?country=${c}`).then((r) => (r.ok ? r.json() : []))))
      .then((results) => {
        const counts = { facture: 0, recu: 0 };
        results.flat().forEach((inv) => {
          counts[inv.doc_type] = (counts[inv.doc_type] || 0) + 1;
        });
        setInvoicesByType([
          { id: "factures", value: counts.facture || 0, color: "#8B5CF6" },
          { id: "recus", value: counts.recu || 0, color: "#F0924B" },
        ]);
      })
      .catch(() => {});

    Promise.all(COUNTRIES.map((c) => fetch(`/api/banking/accounts?country=${c}`).then((r) => (r.ok ? r.json() : []))))
      .then((results) => setBankAccounts(results.flat()))
      .catch(() => {});

    fetch("/api/payroll/payslips")
      .then((r) => (r.ok ? r.json() : []))
      .then((data) => {
        const byPeriod = {};
        (Array.isArray(data) ? data : []).forEach((p) => {
          byPeriod[p.period_label] = (byPeriod[p.period_label] || 0) + p.gross_total;
        });
        setPayrollByPeriod(Object.entries(byPeriod).map(([period, total]) => ({ period, total })));
      })
      .catch(() => {});
  }, []);

  const visaTypes = useMemo(
    () => Array.from(new Set(clients.map((c) => c.visa_type).filter(Boolean))),
    [clients]
  );
  const countries = useMemo(
    () => Array.from(new Set(clients.map((c) => c.country).filter(Boolean))),
    [clients]
  );

  const filtered = clients.filter(
    (c) => (country === "all" || c.country === country) && (visaType === "all" || c.visa_type === visaType)
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
    value: clients.filter((c) => visaStatusOf(c) === s.id).length,
  }));

  // Client countries are free text; translate the ones we know.
  const countryLabel = (c) => {
    const key = `countries.${c.toLowerCase()}`;
    const label = t(key);
    return label === key ? c : label;
  };

  const invoicesByTypeLabeled = invoicesByType.map((i) => ({ ...i, name: t(`statsPage.${i.id}`) }));

  const byCountry = COUNTRIES.map((c) => ({
    name: t(`countries.${c}`),
    value: clients.filter((cl) => cl.country?.toLowerCase() === c).length,
    color: COUNTRY_COLORS[c],
  })).filter((c) => c.value > 0);

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
              {countries.map((c) => (
                <option key={c} value={c}>{countryLabel(c)}</option>
              ))}
            </BoxSelect>
          </div>
          <div>
            <p style={{ marginBottom: "6px", fontSize: "12px", color: "var(--color-muted)" }}>{t("statsPage.visaType")}</p>
            <BoxSelect value={visaType} onChange={(e) => setVisaType(e.target.value)}>
              <option value="all">{t("common.allTypes")}</option>
              {visaTypes.map((v) => (
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
            {country === "all" ? t("common.allCountries") : countryLabel(country)} · {visaType === "all" ? t("statsPage.allVisaTypes") : optionLabel(t, "visaType", visaType)}
          </p>
          <div style={{ height: "280px" }}>
            {series.length === 0 ? (
              <div className="flex-center" style={{ height: "100%", color: "var(--color-muted)", fontSize: "13px" }}>
                {t("statsPage.noClientData")}
              </div>
            ) : (
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={series}>
                  <CartesianGrid stroke="var(--color-line)" vertical={false} />
                  <XAxis dataKey="month" tick={{ fill: "#8a8a8f", fontSize: 12 }} axisLine={false} tickLine={false} />
                  <YAxis allowDecimals={false} tick={{ fill: "#8a8a8f", fontSize: 12 }} axisLine={false} tickLine={false} />
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
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={statusCounts} layout="vertical" margin={{ left: 8, right: 8 }}>
                <XAxis type="number" hide allowDecimals={false} />
                <YAxis type="category" dataKey="name" width={170} interval={0} tick={{ fill: "var(--color-ink)", fontSize: 11 }} axisLine={false} tickLine={false} />
                <Tooltip />
                <Bar dataKey="value" radius={[0, 8, 8, 0]} barSize={14}>
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
              <ResponsiveContainer width="100%" height="100%">
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
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie data={invoicesByTypeLabeled} dataKey="value" nameKey="name" innerRadius={45} outerRadius={75}>
                    {invoicesByTypeLabeled.map((i) => (
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
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={treasuryMonthly}>
                  <CartesianGrid stroke="var(--color-line)" strokeDasharray="3 3" vertical={false} />
                  <XAxis dataKey="month" tick={{ fill: "#8a8a8f", fontSize: 12 }} axisLine={false} tickLine={false} />
                  <YAxis tick={{ fill: "#8a8a8f", fontSize: 12 }} axisLine={false} tickLine={false} />
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
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={bankAccounts} layout="vertical" margin={{ left: 8, right: 8 }}>
                  <XAxis type="number" hide />
                  <YAxis type="category" dataKey="name" width={90} tick={{ fill: "var(--color-ink)", fontSize: 11 }} axisLine={false} tickLine={false} />
                  <Tooltip />
                  <Bar dataKey="balance" name={t("bankingTab.amountCol")} fill="#22c55e" radius={[0, 6, 6, 0]} barSize={14} />
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
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={payrollByPeriod}>
                  <XAxis dataKey="period" tick={{ fill: "#8a8a8f", fontSize: 10 }} axisLine={false} tickLine={false} />
                  <YAxis tick={{ fill: "#8a8a8f", fontSize: 12 }} axisLine={false} tickLine={false} />
                  <Tooltip />
                  <Bar dataKey="total" name={t("payroll.grossTotalCol")} fill="#1F3A5F" radius={[6, 6, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
