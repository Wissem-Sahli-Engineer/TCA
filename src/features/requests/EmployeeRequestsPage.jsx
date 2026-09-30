import { useEffect, useState } from "react";
import { PageTitle } from "../../components/ui/Card";
import { Card } from "../../components/ui/nav";
import { BoxInput, Field } from "../../components/ui/Input";
import { Button } from "../../components/ui/Button";
import { toast } from "../../components/ui/Toast";
import { IconPalmTree, IconWallet, IconCoins } from "../../components/ui/Icons";
import { useAuth } from "../../store/auth";
import { useI18n } from "../../store/i18n";

const BADGE_TONE = {
  approved: "badge-success",
  pending: "badge-warning",
  rejected: "badge-danger",
};

export function EmployeeRequestsPage() {
  const t = useI18n((s) => s.t);
  const user = useAuth((s) => s.user);
  const isAdmin = user?.role === "Admin";
  const [tab, setTab] = useState("vacations");
  const [requests, setRequests] = useState([]);
  const [detail, setDetail] = useState("");
  const [submittedDate, setSubmittedDate] = useState(new Date().toISOString().slice(0, 10));
  const [busy, setBusy] = useState(false);

  const REQUEST_TABS = [
    { id: "vacations", label: t("requests.vacations"), icon: <IconPalmTree size={20} /> },
    { id: "salary-advances", label: t("requests.salaryAdvances"), icon: <IconWallet size={20} /> },
    { id: "loans", label: t("requests.loans"), icon: <IconCoins size={20} /> },
  ];

  const load = () => {
    fetch("/api/employee-requests")
      .then((r) => (r.ok ? r.json() : []))
      .then(setRequests)
      .catch(() => setRequests([]));
  };

  useEffect(load, []);

  const rows = requests.filter((r) => r.category === tab);

  const submit = async (e) => {
    e.preventDefault();
    if (!detail) {
      toast(t("requests.describeRequest"), "err");
      return;
    }
    setBusy(true);
    try {
      const res = await fetch("/api/employee-requests", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          category: tab,
          employee_name: user?.name || "Employee",
          detail,
          submitted_date: submittedDate,
        }),
      });
      if (!res.ok) throw new Error("fail");
      setDetail("");
      load();
      toast(t("requests.submitted"), "ok");
    } catch {
      toast(t("requests.submitFailed"), "err");
    } finally {
      setBusy(false);
    }
  };

  const remove = async (id) => {
    if (!window.confirm(t("requests.removeConfirm"))) return;
    await fetch(`/api/employee-requests/${id}`, { method: "DELETE" }).catch(() => {});
    load();
  };

  return (
    <div className="page-container-max">
      <PageTitle kicker={t("requests.myRequestsKicker")} title={t("requests.employeeRequestsTitle")} />

      <div style={{ width: "100%", display: "flex", justifyContent: "center" }}>
        <Card tabs={REQUEST_TABS} activeTab={tab} onTabChange={setTab} maxWidth={460} />
      </div>

      <form onSubmit={submit} className="card" style={{ display: "grid", gridTemplateColumns: "2fr 1fr auto", gap: "12px", alignItems: "end" }}>
        <Field label={t("requests.detail")}>
          <BoxInput value={detail} onChange={(e) => setDetail(e.target.value)} placeholder={t("requests.detailPlaceholder")} />
        </Field>
        <Field label={t("requests.submissionDate")}>
          <BoxInput type="date" value={submittedDate} onChange={(e) => setSubmittedDate(e.target.value)} />
        </Field>
        <Button variant="brand" type="submit" loading={busy} style={{ top: "-20px" }}>
          {t("requests.submit")}
        </Button>
      </form>

      <div className="card table-wrapper" style={{ marginTop: "50px" }}>
        <table className="data-table">
          <thead>
            <tr>
              <th>{t("requests.employeeCol")}</th>
              <th>{t("requests.detailCol")}</th>
              <th>{t("requests.submittedCol")}</th>
              <th>{t("requests.statusCol")}</th>
              {isAdmin ? <th></th> : null}
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 ? (
              <tr>
                <td colSpan={isAdmin ? 5 : 4} style={{ padding: "32px 16px", textAlign: "center", color: "var(--color-muted)" }}>
                  {t("requests.noRequests")}
                </td>
              </tr>
            ) : (
              rows.map((r) => (
                <tr key={r.id}>
                  <td>{r.employee_name}</td>
                  <td>{r.detail}</td>
                  <td>{r.submitted_date}</td>
                  <td>
                    <span className={`badge ${BADGE_TONE[r.status]}`}>{t(`status.${r.status}`)}</span>
                  </td>
                  {isAdmin ? (
                    <td>
                      <button type="button" onClick={() => remove(r.id)} style={{ color: "var(--color-danger)", fontSize: "12px", fontWeight: "600" }}>
                        {t("requests.remove")}
                      </button>
                    </td>
                  ) : null}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
