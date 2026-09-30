import { useEffect, useState } from "react";
import { PageTitle } from "../../components/ui/Card";
import { BoxSelect } from "../../components/ui/Input";
import { toast } from "../../components/ui/Toast";
import { useAuth } from "../../store/auth";
import { useI18n } from "../../store/i18n";

const STATUS_TONE = {
  active: "badge-success",
  pending: "badge-warning",
  rejected: "badge-danger",
};

export function UsersPage() {
  const t = useI18n((s) => s.t);
  const currentUser = useAuth((s) => s.user);
  const [users, setUsers] = useState([]);
  const [busyId, setBusyId] = useState(null);

  const load = () => {
    fetch("/api/auth/users")
      .then((r) => (r.ok ? r.json() : []))
      .then(setUsers)
      .catch(() => setUsers([]));
  };

  useEffect(load, []);

  const act = async (id, action) => {
    setBusyId(id);
    try {
      const res = await fetch(`/api/auth/users/${id}/${action}`, { method: "POST" });
      if (!res.ok) throw new Error("fail");
      load();
      toast(action === "approve" ? t("users.approved") : t("users.rejectedMsg"), "ok");
    } catch {
      toast(t("users.updateFailed"), "err");
    } finally {
      setBusyId(null);
    }
  };

  const changeRole = async (id, role) => {
    setBusyId(id);
    try {
      const res = await fetch(`/api/auth/users/${id}/role`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ role }),
      });
      if (!res.ok) throw new Error("fail");
      load();
      toast(`${t("users.roleChanged")} ${t(`roles.${role}`)}`, "ok");
    } catch {
      toast(t("users.roleChangeFailed"), "err");
    } finally {
      setBusyId(null);
    }
  };

  const remove = async (id) => {
    if (!window.confirm(t("users.removeConfirm"))) return;
    setBusyId(id);
    try {
      const res = await fetch(`/api/auth/users/${id}`, { method: "DELETE" });
      if (!res.ok) throw new Error("fail");
      load();
      toast(t("users.removed"), "ok");
    } catch {
      toast(t("users.removeFailed"), "err");
    } finally {
      setBusyId(null);
    }
  };

  const pending = users.filter((u) => u.status === "pending");
  const others = users.filter((u) => u.status !== "pending");

  return (
    <div className="page-container-max">
      <PageTitle kicker={t("users.kicker")} title={t("users.title")} />

      {pending.length > 0 ? (
        <div className="card table-wrapper" style={{ marginBottom: "24px" }}>
          <h2 style={{ marginBottom: "12px", fontSize: "16px", fontWeight: "700" }}>{t("users.pendingRequests")}</h2>
          <table className="data-table">
            <thead>
              <tr>
                <th>{t("users.nameCol")}</th>
                <th>{t("users.emailCol")}</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {pending.map((u) => (
                <tr key={u.id}>
                  <td>{u.name}</td>
                  <td>{u.email}</td>
                  <td style={{ display: "flex", gap: "8px" }}>
                    <button
                      type="button"
                      disabled={busyId === u.id}
                      onClick={() => act(u.id, "approve")}
                      className="btn btn-brand"
                      style={{ width: "auto", padding: "6px 14px", fontSize: "12px" }}
                    >
                      {t("users.approve")}
                    </button>
                    <button
                      type="button"
                      disabled={busyId === u.id}
                      onClick={() => act(u.id, "reject")}
                      style={{ color: "var(--color-danger)", fontSize: "12px", fontWeight: "600" }}
                    >
                      {t("users.reject")}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}

      <div className="card table-wrapper">
        <h2 style={{ marginBottom: "12px", fontSize: "16px", fontWeight: "700" }}>{t("users.allAccounts")}</h2>
        <table className="data-table">
          <thead>
            <tr>
              <th>{t("users.nameCol")}</th>
              <th>{t("users.emailCol")}</th>
              <th>{t("users.roleCol")}</th>
              <th>{t("users.statusCol")}</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {others.length === 0 ? (
              <tr>
                <td colSpan={5} style={{ padding: "32px 16px", textAlign: "center", color: "var(--color-muted)" }}>
                  {t("users.noAccounts")}
                </td>
              </tr>
            ) : (
              others.map((u) => (
                <tr key={u.id}>
                  <td>{u.name}</td>
                  <td>{u.email}</td>
                  <td style={{ maxWidth: "140px" }}>
                    {u.id !== currentUser?.id ? (
                      <BoxSelect
                        value={u.role}
                        disabled={busyId === u.id}
                        onChange={(e) => changeRole(u.id, e.target.value)}
                      >
                        <option value="Agent">{t("roles.Agent")}</option>
                        <option value="Admin">{t("roles.Admin")}</option>
                      </BoxSelect>
                    ) : (
                      t(`roles.${u.role}`)
                    )}
                  </td>
                  <td>
                    <span className={`badge ${STATUS_TONE[u.status] || "badge-brand"}`}>{t(`status.${u.status}`)}</span>
                  </td>
                  <td>
                    {u.id !== currentUser?.id ? (
                      <button
                        type="button"
                        disabled={busyId === u.id}
                        onClick={() => remove(u.id)}
                        style={{ color: "var(--color-danger)", fontSize: "12px", fontWeight: "600" }}
                      >
                        {t("users.remove")}
                      </button>
                    ) : (
                      <span style={{ fontSize: "12px", color: "var(--color-muted)" }}>{t("users.you")}</span>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
