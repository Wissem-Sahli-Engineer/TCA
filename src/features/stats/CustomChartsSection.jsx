import { useEffect, useState } from "react";
import { IconPlus } from "../../components/ui/Icons";
import { useAuth } from "../../store/auth";
import { useI18n } from "../../store/i18n";
import { ChartBuilder } from "./ChartBuilder";
import { CustomChart } from "./CustomChart";
import { fetchChartRows, periodLabel } from "./customCharts";

function SavedChartCard({ chart, onRemove }) {
  const t = useI18n((s) => s.t);
  const [rows, setRows] = useState(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    fetchChartRows(chart)
      .then((data) => !cancelled && setRows(data))
      .catch(() => !cancelled && setFailed(true));
    return () => {
      cancelled = true;
    };
  }, [chart]);

  const subtitle = [
    t(`customCharts.sources.${chart.source}`),
    t(`customCharts.metrics.${chart.metric}`),
    chart.country ? t(`countries.${chart.country}`) : null,
    periodLabel(t, chart.months),
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <div className="col-6 card">
      <div className="flex-between" style={{ alignItems: "flex-start", gap: "12px", marginBottom: "14px" }}>
        <div style={{ minWidth: 0 }}>
          <h3 style={{ fontSize: "16px", fontWeight: "700", color: "var(--color-ink)" }}>{chart.title}</h3>
          <p style={{ marginTop: "2px", fontSize: "12px", color: "var(--color-muted)" }}>
            {t(`customCharts.dims.${chart.group_by}`)} · {subtitle}
          </p>
        </div>
        <button
          type="button"
          onClick={() => onRemove(chart)}
          title={t("customCharts.remove")}
          aria-label={t("customCharts.remove")}
          style={{ color: "var(--color-danger)", fontSize: "12px", fontWeight: "600", flexShrink: 0 }}
        >
          {t("common.remove")}
        </button>
      </div>
      {failed ? (
        <p style={{ color: "var(--color-muted)", fontSize: "13px" }}>{t("customCharts.loadFailed")}</p>
      ) : rows === null ? (
        <p style={{ color: "var(--color-muted)", fontSize: "13px" }}>{t("common.loading")}</p>
      ) : (
        <CustomChart chart={chart} rows={rows} />
      )}
    </div>
  );
}

// The user's own charts on the Stats page (stored per account on the server,
// so the iOS app shows the same ones).
export function CustomChartsSection() {
  const t = useI18n((s) => s.t);
  const isAdmin = useAuth((s) => s.user?.role === "Admin");
  const [charts, setCharts] = useState([]);
  const [building, setBuilding] = useState(false);

  const load = () => {
    fetch("/api/stats/charts")
      .then((r) => (r.ok ? r.json() : []))
      .then(setCharts)
      .catch(() => setCharts([]));
  };

  useEffect(load, []);

  const remove = async (chart) => {
    if (!window.confirm(t("customCharts.removeConfirm"))) return;
    await fetch(`/api/stats/charts/${chart.id}`, { method: "DELETE" }).catch(() => {});
    load();
  };

  return (
    <section style={{ marginTop: "32px" }}>
      <div className="flex-between" style={{ gap: "16px", flexWrap: "wrap", marginBottom: "16px" }}>
        <div>
          <h2 style={{ fontSize: "20px", fontWeight: "700", color: "var(--color-ink)" }}>{t("customCharts.title")}</h2>
          <p style={{ marginTop: "4px", fontSize: "13px", color: "var(--color-muted)" }}>{t("customCharts.subtitle")}</p>
        </div>
        <button
          type="button"
          className="btn btn-brand"
          onClick={() => setBuilding(true)}
          style={{ width: "auto", display: "inline-flex", gap: "8px", padding: "10px 18px" }}
        >
          <IconPlus size={16} />
          {t("customCharts.add")}
        </button>
      </div>

      {charts.length === 0 ? (
        <div className="card" style={{ padding: "32px", textAlign: "center", color: "var(--color-muted)", fontSize: "14px" }}>
          {t("customCharts.empty")}
        </div>
      ) : (
        <div className="grid-12">
          {charts.map((chart) => (
            <SavedChartCard key={chart.id} chart={chart} onRemove={remove} />
          ))}
        </div>
      )}

      {building ? (
        <ChartBuilder
          isAdmin={isAdmin}
          onClose={() => setBuilding(false)}
          onSaved={() => {
            setBuilding(false);
            load();
          }}
        />
      ) : null}
    </section>
  );
}
