import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { Button } from "../../components/ui/Button";
import { BoxInput, BoxSelect, Field } from "../../components/ui/Input";
import { toast } from "../../components/ui/Toast";
import { useI18n } from "../../store/i18n";
import { CustomChart } from "./CustomChart";
import { CHART_SOURCES, CHART_TYPES, PERIODS, chartQuery, fetchChartRows, periodLabel, sourcesFor } from "./customCharts";

const INITIAL = {
  title: "",
  chart_type: "bar",
  source: "clients",
  group_by: "visa_status",
  metric: "count",
  country: "",
  months: "",
};

// Keep the definition valid for its data source (fields differ per source).
function fitToSource(chart) {
  const source = CHART_SOURCES[chart.source];
  return {
    ...chart,
    group_by: source.dims.includes(chart.group_by) ? chart.group_by : source.dims[0],
    metric: source.metrics.includes(chart.metric) ? chart.metric : "count",
    country: source.country ? chart.country : "",
    months: source.dated ? chart.months : "",
  };
}

// Modal to define a custom chart, with a live preview, then save it.
export function ChartBuilder({ isAdmin, onClose, onSaved }) {
  const t = useI18n((s) => s.t);
  const [chart, setChart] = useState(INITIAL);
  const [rows, setRows] = useState(null);
  const [busy, setBusy] = useState(false);

  const source = CHART_SOURCES[chart.source];
  const set = (key) => (e) => setChart((c) => fitToSource({ ...c, [key]: e.target.value }));

  const queryKey = JSON.stringify(chartQuery(chart));
  useEffect(() => {
    let cancelled = false;
    setRows(null);
    const timer = setTimeout(() => {
      fetchChartRows(chart)
        .then((data) => !cancelled && setRows(data))
        .catch(() => !cancelled && setRows([]));
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [queryKey]);

  useEffect(() => {
    const onKey = (e) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const save = async () => {
    if (!chart.title.trim()) return toast(t("customCharts.titleRequired"), "err");
    setBusy(true);
    try {
      const res = await fetch("/api/stats/charts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...chartQuery(chart), title: chart.title.trim(), chart_type: chart.chart_type }),
      });
      if (!res.ok) throw new Error("fail");
      toast(t("customCharts.saved"), "ok");
      onSaved();
    } catch {
      toast(t("customCharts.saveFailed"), "err");
    } finally {
      setBusy(false);
    }
  };

  // Rendered on <body>: the page wrapper is animated (transformed), which
  // would otherwise confine a position:fixed overlay to the content area.
  return createPortal(
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal-card" role="dialog" aria-modal="true" aria-label={t("customCharts.newChart")}>
        <div className="flex-between" style={{ marginBottom: "16px" }}>
          <h2 style={{ fontSize: "18px", fontWeight: "700" }}>{t("customCharts.newChart")}</h2>
          <button type="button" onClick={onClose} aria-label={t("common.close")} style={{ fontSize: "20px", color: "var(--color-muted)" }}>
            ×
          </button>
        </div>

        <div className="chart-builder-grid">
          <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
            <Field label={t("customCharts.chartTitle")}>
              <BoxInput value={chart.title} onChange={set("title")} placeholder={t("customCharts.titlePlaceholder")} autoFocus />
            </Field>
            <Field label={t("customCharts.source")}>
              <BoxSelect value={chart.source} onChange={set("source")}>
                {sourcesFor(isAdmin).map((id) => (
                  <option key={id} value={id}>{t(`customCharts.sources.${id}`)}</option>
                ))}
              </BoxSelect>
            </Field>
            <Field label={t("customCharts.groupBy")}>
              <BoxSelect value={chart.group_by} onChange={set("group_by")}>
                {source.dims.map((id) => (
                  <option key={id} value={id}>{t(`customCharts.dims.${id}`)}</option>
                ))}
              </BoxSelect>
            </Field>
            <Field label={t("customCharts.metric")}>
              <BoxSelect value={chart.metric} onChange={set("metric")}>
                {source.metrics.map((id) => (
                  <option key={id} value={id}>{t(`customCharts.metrics.${id}`)}</option>
                ))}
              </BoxSelect>
            </Field>
            <Field label={t("customCharts.chartType")}>
              <div className="chart-type-picker">
                {CHART_TYPES.map((id) => (
                  <button
                    key={id}
                    type="button"
                    className={chart.chart_type === id ? "active" : ""}
                    onClick={() => setChart((c) => ({ ...c, chart_type: id }))}
                  >
                    {t(`customCharts.types.${id}`)}
                  </button>
                ))}
              </div>
            </Field>
            {source.country ? (
              <Field label={t("customCharts.country")}>
                <BoxSelect value={chart.country} onChange={set("country")}>
                  <option value="">{t("common.allCountries")}</option>
                  <option value="tunisia">{t("countries.tunisia")}</option>
                  <option value="libya">{t("countries.libya")}</option>
                </BoxSelect>
              </Field>
            ) : null}
            {source.dated ? (
              <Field label={t("customCharts.period")}>
                <BoxSelect value={chart.months} onChange={set("months")}>
                  <option value="">{periodLabel(t, null)}</option>
                  {PERIODS.map((m) => (
                    <option key={m} value={m}>{periodLabel(t, m)}</option>
                  ))}
                </BoxSelect>
              </Field>
            ) : null}
          </div>

          <div style={{ minWidth: 0 }}>
            <p className="payroll-step">{t("customCharts.preview")}</p>
            <div className="card" style={{ padding: "16px" }}>
              <p style={{ marginBottom: "12px", fontSize: "15px", fontWeight: "700" }}>
                {chart.title.trim() || t("customCharts.titlePlaceholder")}
              </p>
              {rows === null ? (
                <div className="flex-center" style={{ height: "200px", color: "var(--color-muted)", fontSize: "13px" }}>
                  {t("common.loading")}
                </div>
              ) : (
                <CustomChart chart={chart} rows={rows} />
              )}
            </div>
          </div>
        </div>

        <div style={{ display: "flex", gap: "10px", justifyContent: "flex-end", marginTop: "18px" }}>
          <div style={{ width: "140px" }}>
            <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
          </div>
          <div style={{ width: "200px" }}>
            <Button variant="brand" loading={busy} onClick={save}>{t("customCharts.save")}</Button>
          </div>
        </div>
      </div>
    </div>,
    document.body
  );
}
