import { useState, useEffect } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { PageTitle } from "../../components/ui/Card";
import { Card } from "../../components/ui/nav";
import { InvoicesTab } from "./InvoicesTab";
import { TreasuryTab } from "./TreasuryTab";
import { BankingTab } from "./BankingTab";
import { StatsTab } from "./StatsTab";
import { useI18n } from "../../store/i18n";

function accountingTabs(t) {
  return [
    { id: "invoices", label: t("accounting.invoices") },
    { id: "treasury", label: t("accounting.treasury") },
    { id: "banking", label: t("accounting.banking") },
    { id: "stats", label: t("accounting.stats") },
  ];
}

const COUNTRY_META = {
  tunisia: { currency: "TND", flag: "🇹🇳" },
  libya: { currency: "LYD", flag: "🇱🇾" },
};

export function AccountingPage({ defaultCountry = "tunisia" }) {
  const location = useLocation();
  const navigate = useNavigate();
  const t = useI18n((s) => s.t);
  const ACCOUNTING_TABS = accountingTabs(t);

  const currentCountry = location.pathname.includes("libya")
    ? "libya"
    : location.pathname.includes("tunisia")
    ? "tunisia"
    : defaultCountry;

  const [country, setCountry] = useState(currentCountry);
  const [tab, setTab] = useState("invoices");
  const [summary, setSummary] = useState({ invoiceCount: 0, monthSpending: 0, bankTotal: 0 });

  useEffect(() => {
    if (location.pathname.includes("libya")) setCountry("libya");
    else if (location.pathname.includes("tunisia")) setCountry("tunisia");
  }, [location.pathname]);

  const meta = { ...(COUNTRY_META[country] || COUNTRY_META.tunisia), label: t(`countries.${country}`) };

  useEffect(() => {
    Promise.all([
      fetch(`/api/invoices?country=${country}`).then((r) => (r.ok ? r.json() : [])),
      fetch(`/api/treasury?country=${country}`).then((r) => (r.ok ? r.json() : null)),
      fetch(`/api/banking/accounts?country=${country}`).then((r) => (r.ok ? r.json() : [])),
    ])
      .then(([invoices, treasury, accounts]) => {
        setSummary({
          invoiceCount: Array.isArray(invoices) ? invoices.length : 0,
          monthSpending: treasury?.current_month?.spending || 0,
          bankTotal: Array.isArray(accounts) ? accounts.reduce((acc, a) => acc + a.balance, 0) : 0,
        });
      })
      .catch(() => {});
  }, [country, tab]);

  const handleCountryChange = (c) => {
    setCountry(c);
    navigate(`/accounting/${c}`);
  };

  return (
    <div className="page-container-max">
      {/* Top Header & Country Toggle */}
      <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", justifyContent: "space-between", gap: "16px", marginBottom: "16px" }}>
        <PageTitle
          kicker={`${t("accounting.financialOps")} — ${meta.label}`}
          title={`${t("accounting.accountingTitle")} (${meta.flag} ${meta.label})`}
        />

      </div>

      {/* Floating Card Navigation Bar for Invoices, Treasury, Banking, Stats */}
      <div style={{ width: "100%", display: "flex", justifyContent: "center" }}>
        <Card
          tabs={ACCOUNTING_TABS}
          activeTab={tab}
          onTabChange={setTab}
          maxWidth={460}
        />
      </div>

      {/* Overview Stat Badges */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: "16px", marginBottom: "24px" }}>
        <div className="card" style={{ padding: "16px 20px" }}>
          <p style={{ fontSize: "11px", fontWeight: "700", textTransform: "uppercase", letterSpacing: "0.08em", color: "var(--color-muted)" }}>
            {t("accounting.invoicesReceipts")}
          </p>
          <p style={{ marginTop: "6px", fontSize: "22px", fontWeight: "700", color: "var(--color-ink)" }}>
            {summary.invoiceCount}
          </p>
        </div>
        <div className="card" style={{ padding: "16px 20px" }}>
          <p style={{ fontSize: "11px", fontWeight: "700", textTransform: "uppercase", letterSpacing: "0.08em", color: "var(--color-muted)" }}>
            {t("accounting.monthlyOutflow")}
          </p>
          <p style={{ marginTop: "6px", fontSize: "22px", fontWeight: "700", color: "var(--color-accent-orange)" }}>
            {meta.currency} {summary.monthSpending.toLocaleString()}
          </p>
        </div>
        <div className="card" style={{ padding: "16px 20px" }}>
          <p style={{ fontSize: "11px", fontWeight: "700", textTransform: "uppercase", letterSpacing: "0.08em", color: "var(--color-muted)" }}>
            {t("accounting.bankReserves")} ({meta.currency})
          </p>
          <p style={{ marginTop: "6px", fontSize: "22px", fontWeight: "700", color: "var(--color-success)" }}>
            {meta.currency} {summary.bankTotal.toLocaleString()}
          </p>
        </div>
      </div>

      {tab === "invoices" && <InvoicesTab country={country} />}
      {tab === "treasury" && <TreasuryTab country={country} currency={meta.currency} />}
      {tab === "banking" && <BankingTab country={country} currency={meta.currency} flag={meta.flag} />}
      {tab === "stats" && <StatsTab country={country} currency={meta.currency} />}
    </div>
  );
}

export default AccountingPage;
