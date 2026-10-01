import { useEffect, useState } from "react";
import { PageTitle } from "../../components/ui/Card";
import { BoxInput, BoxSelect, Field } from "../../components/ui/Input";
import { Button } from "../../components/ui/Button";
import { toast } from "../../components/ui/Toast";
import { useI18n } from "../../store/i18n";

// Same defaults as paie_app.html's "Paramètres avancés".
const DEFAULT_SETTINGS = {
  pause: "60",
  m25: "25",
  m50: "50",
  m100: "100",
  company_name: "شركة تونس للإستشارات والمساعدة",
  company_address: "عدد 85 شارع فلسطين عمارة القدس الطابق الثاني مكتب رقم 3 تونس، 1010",
  company_contact: "info@tunis-consulting.com — +216 29 190 039 | +216 28 846 888",
};

async function fetchPdf(id) {
  const res = await fetch(`/api/payroll/payslips/${id}/pdf`);
  if (!res.ok) throw new Error("fail");
  return URL.createObjectURL(await res.blob());
}

export function PayrollPage() {
  const t = useI18n((s) => s.t);
  const [fileName, setFileName] = useState("");
  const [employees, setEmployees] = useState([]);
  const [selected, setSelected] = useState(0);
  const [rate, setRate] = useState("");
  const [advances, setAdvances] = useState("0");
  const [settings, setSettings] = useState(DEFAULT_SETTINGS);
  const [uploading, setUploading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [current, setCurrent] = useState(null);
  const [previewUrl, setPreviewUrl] = useState("");
  const [history, setHistory] = useState([]);

  const loadHistory = () => {
    fetch("/api/payroll/payslips")
      .then((r) => (r.ok ? r.json() : []))
      .then(setHistory)
      .catch(() => setHistory([]));
  };

  useEffect(loadHistory, []);
  useEffect(() => () => previewUrl && URL.revokeObjectURL(previewUrl), [previewUrl]);

  const setSetting = (key) => (e) => setSettings((s) => ({ ...s, [key]: e.target.value }));

  const onFile = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    setUploading(true);
    const body = new FormData();
    body.append("file", file);
    try {
      const res = await fetch("/api/payroll/parse-pointage", { method: "POST", body });
      if (!res.ok) throw new Error("fail");
      const data = await res.json();
      if (!data.length) throw new Error("empty");
      setEmployees(data);
      setSelected(0);
      setFileName(file.name);
      toast(`${t("payroll.parsed")} ${data.length} ${t("payroll.employeesWord")}`, "ok");
    } catch {
      toast(t("payroll.readFailed"), "err");
    } finally {
      setUploading(false);
    }
  };

  const showPayslip = async (payslip) => {
    setCurrent(payslip);
    setPreviewUrl("");
    try {
      setPreviewUrl(await fetchPdf(payslip.id));
    } catch {
      toast(t("payroll.downloadFailed"), "err");
    }
  };

  const generate = async () => {
    const emp = employees[selected];
    if (!emp) return toast(t("payroll.uploadFirst"), "err");
    if (!(Number(rate) > 0)) return toast(t("payroll.enterRate"), "err");
    setBusy(true);
    try {
      const res = await fetch("/api/payroll/payslips", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          employee_name: emp.employee_name,
          matricule: emp.matricule,
          rows: emp.rows,
          hourly_rate: Number(rate),
          advances: Number(advances) || 0,
          pause: Number(settings.pause) || 0,
          m25: Number(settings.m25) || 0,
          m50: Number(settings.m50) || 0,
          m100: Number(settings.m100) || 0,
          company_name: settings.company_name,
          company_address: settings.company_address,
          company_contact: settings.company_contact,
          currency: "TND",
        }),
      });
      if (!res.ok) throw new Error("fail");
      const payslip = await res.json();
      loadHistory();
      toast(t("payroll.generated"), "ok");
      await showPayslip(payslip);
    } catch {
      toast(t("payroll.generateFailed"), "err");
    } finally {
      setBusy(false);
    }
  };

  const removePayslip = async (id) => {
    if (!window.confirm(t("payroll.removeConfirm"))) return;
    await fetch(`/api/payroll/payslips/${id}`, { method: "DELETE" }).catch(() => {});
    if (current?.id === id) {
      setCurrent(null);
      setPreviewUrl("");
    }
    loadHistory();
  };

  const downloadPayslip = async (p) => {
    try {
      const url = await fetchPdf(p.id);
      const a = document.createElement("a");
      a.href = url;
      a.download = `fiche-de-paie-${p.employee_name}-${p.period_label.replace("/", "-")}.pdf`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    } catch {
      toast(t("payroll.downloadFailed"), "err");
    }
  };

  const d = current?.details;
  const emp = employees[selected];

  return (
    <div className="page-container-max">
      <PageTitle kicker={t("payroll.kicker")} title={t("payroll.title")} />

      <div className="payroll-grid">
        {/* ---------- controls ---------- */}
        <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          <div className="card">
            <h2 className="payroll-step">{t("payroll.step1")}</h2>
            <label className="upload-dropzone" style={{ display: "block", textAlign: "center" }}>
              <div style={{ fontWeight: "600", fontSize: "14px", color: "var(--color-ink)" }}>
                {uploading ? t("payroll.reading") : t("payroll.uploadPointage")}
              </div>
              <div style={{ marginTop: "4px", fontSize: "12px", color: "var(--color-muted)" }}>{t("payroll.columnsHint")}</div>
              <input type="file" accept=".xls,.xlsx" style={{ display: "none" }} onChange={onFile} />
            </label>
            {fileName ? (
              <p style={{ marginTop: "8px", fontSize: "12.5px", fontWeight: "600", color: "var(--color-success)" }}>
                ✓ {fileName} — {employees.length} {t("payroll.fileLoaded")} {emp?.days} {t("payroll.daysWord")}
              </p>
            ) : null}
            {employees.length > 1 ? (
              <div style={{ marginTop: "12px" }}>
                <Field label={t("payroll.employee")}>
                  <BoxSelect value={selected} onChange={(e) => setSelected(Number(e.target.value))}>
                    {employees.map((e, i) => (
                      <option key={e.emp_no} value={i}>
                        {e.employee_name} ({e.matricule})
                      </option>
                    ))}
                  </BoxSelect>
                </Field>
              </div>
            ) : null}
          </div>

          <div className="card">
            <h2 className="payroll-step">{t("payroll.step2")}</h2>
            <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
              <Field label={t("payroll.baseRate")}>
                <BoxInput type="number" step="0.001" min="0" placeholder="5.769" value={rate} onChange={(e) => setRate(e.target.value)} />
              </Field>
              <Field label={t("payroll.advances")}>
                <BoxInput type="number" step="0.001" min="0" value={advances} onChange={(e) => setAdvances(e.target.value)} />
              </Field>
            </div>
          </div>

          <details className="card payroll-advanced">
            <summary>{t("payroll.advanced")}</summary>
            <div style={{ display: "flex", flexDirection: "column", gap: "12px", marginTop: "12px" }}>
              <Field label={t("payroll.pause")}>
                <BoxInput type="number" min="0" step="1" value={settings.pause} onChange={setSetting("pause")} />
              </Field>
              <div className="grid-2" style={{ gap: "12px" }}>
                <Field label={t("payroll.m25")}>
                  <BoxInput type="number" step="1" value={settings.m25} onChange={setSetting("m25")} />
                </Field>
                <Field label={t("payroll.m50")}>
                  <BoxInput type="number" step="1" value={settings.m50} onChange={setSetting("m50")} />
                </Field>
                <Field label={t("payroll.m100")}>
                  <BoxInput type="number" step="1" value={settings.m100} onChange={setSetting("m100")} />
                </Field>
              </div>
              <Field label={t("payroll.company")}>
                <BoxInput dir="rtl" value={settings.company_name} onChange={setSetting("company_name")} />
              </Field>
              <Field label={t("payroll.address")}>
                <BoxInput dir="rtl" value={settings.company_address} onChange={setSetting("company_address")} />
              </Field>
              <Field label={t("payroll.contact")}>
                <BoxInput dir="ltr" value={settings.company_contact} onChange={setSetting("company_contact")} />
              </Field>
            </div>
          </details>

          <Button variant="brand" loading={busy} disabled={!emp || !(Number(rate) > 0)} onClick={generate}>
            {t("payroll.generate")}
          </Button>
        </div>

        {/* ---------- preview ---------- */}
        <div style={{ minWidth: 0 }}>
          {d ? (
            <>
              <div className="payroll-tiles">
                <div className="card payroll-tile">
                  <span>{t("payroll.daysWorked")}</span>
                  <strong>{d.jours ?? "—"}</strong>
                </div>
                <div className="card payroll-tile">
                  <span>{t("payroll.absences")}</span>
                  <strong>{d.abs ?? "—"}</strong>
                </div>
                <div className="card payroll-tile">
                  <span>
                    {t("payroll.overtime")} {d.m25 != null ? `+${d.m25}%` : ""}
                  </span>
                  <strong>{d.sup_hm}</strong>
                </div>
                <div className="card payroll-tile payroll-tile-net">
                  <span>{t("payroll.netToPay")}</span>
                  <strong>{Number(current.net_total).toFixed(3)}</strong>
                </div>
              </div>
              <div className="card" style={{ padding: 0, overflow: "hidden" }}>
                {previewUrl ? (
                  <iframe title="payslip" src={previewUrl} style={{ width: "100%", height: "78vh", border: 0, display: "block" }} />
                ) : (
                  <p style={{ padding: "40px", textAlign: "center", color: "var(--color-muted)" }}>{t("common.loading")}</p>
                )}
              </div>
              <div style={{ marginTop: "12px", maxWidth: "260px" }}>
                <Button variant="brand" onClick={() => downloadPayslip(current)}>
                  {t("payroll.downloadPdf")}
                </Button>
              </div>
            </>
          ) : (
            <div className="card payroll-empty">
              <div style={{ fontSize: "36px" }}>🧾</div>
              <h3>{t("payroll.emptyTitle")}</h3>
              <p>{t("payroll.emptyText")}</p>
            </div>
          )}
        </div>
      </div>

      <p style={{ margin: "14px 0 24px", fontSize: "11.5px", color: "var(--color-muted)", textAlign: "center" }}>{t("payroll.formula")}</p>

      <div className="card" style={{ padding: 0, overflow: "hidden" }}>
        <div style={{ padding: "16px 20px", borderBottom: "1px solid var(--color-line)" }}>
          <h2 style={{ fontSize: "16px", fontWeight: "700" }}>{t("payroll.generatedPayslips")}</h2>
        </div>
        <div className="table-wrapper">
          <table className="data-table">
            <thead>
              <tr>
                <th>{t("payroll.employeeCol")}</th>
                <th>{t("payroll.periodCol")}</th>
                <th>{t("payroll.hoursCol")}</th>
                <th>{t("payroll.grossTotalCol")}</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {history.length === 0 ? (
                <tr>
                  <td colSpan={5} style={{ padding: "32px 16px", textAlign: "center", color: "var(--color-muted)" }}>
                    {t("payroll.noPayslips")}
                  </td>
                </tr>
              ) : (
                history.map((p) => (
                  <tr key={p.id} style={current?.id === p.id ? { background: "var(--color-brand-wash)" } : undefined}>
                    <td>
                      <button type="button" onClick={() => showPayslip(p)} style={{ fontWeight: "600", color: "var(--color-brand)" }}>
                        {p.employee_name}
                      </button>
                    </td>
                    <td>{p.period_label}</td>
                    <td>{p.hours}</td>
                    <td>
                      {p.currency} {Number(p.net_total).toFixed(3)}
                    </td>
                    <td style={{ display: "flex", gap: "8px" }}>
                      <button
                        type="button"
                        onClick={() => downloadPayslip(p)}
                        className="btn btn-brand"
                        style={{ width: "auto", padding: "6px 14px", fontSize: "12px", display: "inline-flex" }}
                      >
                        {t("payroll.downloadPdf")}
                      </button>
                      <button
                        type="button"
                        onClick={() => removePayslip(p.id)}
                        style={{ color: "var(--color-danger)", fontSize: "12px", fontWeight: "600" }}
                      >
                        {t("payroll.remove")}
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
