import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { PageTitle } from "../../components/ui/Card";
import { IconPlus } from "../../components/ui/Icons";
import { Card } from "../../components/ui/nav";
import Magnet from "../../components/ui/magnet";
import { useDebounced, usePagedList } from "../../lib/usePagedList";
import { withToken } from "../../store/auth";
import { useI18n } from "../../store/i18n";
import { alertReasons, alertText, optionLabel, paymentTone, visaStatusOf, visaTone } from "./options";

// The "All clients" tab is id "normal" here; the server calls it "all". Search,
// tabs (fair / reservation / alert) and paging are all done by the server.
const SERVER_TAB = { normal: "all", fair: "fair", reservation: "reservation", alert: "alert" };

export function ClientsPage() {
  const navigate = useNavigate();
  const t = useI18n((s) => s.t);
  const [query, setQuery] = useState("");
  const [tab, setTab] = useState("normal");
  const q = useDebounced(query.trim(), 300);
  const { items: clients, total, loading, loadingMore, error, hasMore, loadMore } = usePagedList("/api/clients", {
    q,
    tab: SERVER_TAB[tab],
  });

  const CLIENTS_TABS = [
    { id: "normal", label: t("clients.tabAll") },
    { id: "fair", label: t("clients.tabFair") },
    { id: "reservation", label: t("clients.tabReservation") },
    { id: "alert", label: t("clients.tabAlert") },
  ];

  return (
    <div className="page-container-max">
      <div style={{ width: "100%", display: "flex", justifyContent: "center" }}>
        <Card tabs={CLIENTS_TABS} activeTab={tab} onTabChange={setTab} maxWidth={460} />
      </div>

      <PageTitle
        kicker={t("clients.kicker")}
        title={t("clients.title")}
        action={
          <Magnet padding={26} magnetStrength={14}>
            <Link
              to="/clients/add"
              className="btn btn-brand"
              style={{ width: "auto", display: "inline-flex", gap: "8px", padding: "10px 18px" }}
            >
              <IconPlus size={16} />
              {t("clients.addClient")}
            </Link>
          </Magnet>
        }
      />

      <div style={{ marginBottom: "20px" }}>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={t("clients.filterPlaceholder")}
          className="input-box"
          style={{ maxWidth: "380px" }}
        />
      </div>

      <div className="card" style={{ padding: "0", overflow: "hidden" }}>
        <div className="table-wrapper">
          <table className="data-table">
            <thead>
              <tr>
                <th style={{ width: "64px" }}>{t("clients.photo")}</th>
                <th>{t("clients.name")}</th>
                <th>{t("clients.passport")}</th>
                <th>{t("clients.phone")}</th>
                <th>{t("clients.nationality")}</th>
                <th>{t("clients.visaStatus")}</th>
                <th>{t("clients.paymentState")}</th>
              </tr>
            </thead>
            <tbody>
              {clients.length === 0 ? (
                <tr>
                  <td colSpan={7} style={{ padding: "40px 16px", textAlign: "center", color: "var(--color-muted)" }}>
                    {loading ? t("common.loading") : error ? t("clients.serverError") : t("clients.noMatches")}
                  </td>
                </tr>
              ) : (
                clients.map((c) => (
                  <tr
                    key={c.id}
                    onClick={() => navigate(`/clients/${c.id}`)}
                    style={{ cursor: "pointer" }}
                  >
                    <td>
                      {c.user_photo ? (
                        <img src={withToken(c.user_photo)} alt="" className="table-thumbnail" />
                      ) : (
                        <div
                          className="table-thumbnail flex-center"
                          style={{ backgroundColor: "var(--color-surface)", fontSize: "10px", color: "var(--color-muted)" }}
                        >
                          —
                        </div>
                      )}
                    </td>
                    <td style={{ fontWeight: "600", color: "var(--color-ink)" }}>
                      {c.given_name} {c.surname}
                      {alertReasons(c).map((r) => (
                        <div key={r.id} style={{ marginTop: "2px", fontSize: "11.5px", fontWeight: "500", color: "var(--color-danger)" }}>
                          ⚠ {alertText(t, r)}
                        </div>
                      ))}
                    </td>
                    <td style={{ fontFamily: "monospace", fontSize: "13px" }}>{c.passport_number}</td>
                    <td style={{ color: "var(--color-muted)" }}>{c.phone}</td>
                    <td>{c.nationality}</td>
                    <td>
                      <span className={`badge ${visaTone(visaStatusOf(c))}`}>
                        {optionLabel(t, "visa", visaStatusOf(c))}
                      </span>
                    </td>
                    <td>
                      {c.payment_state ? (
                        <span className={`badge ${paymentTone(c.payment_state)}`}>
                          {optionLabel(t, "payment", c.payment_state)}
                        </span>
                      ) : (
                        <span style={{ color: "var(--color-muted)" }}>—</span>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {total > 0 ? (
        <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: "16px", marginTop: "16px" }}>
          <span style={{ fontSize: "13px", color: "var(--color-muted)" }}>
            {t("clients.showing").replace("{n}", clients.length).replace("{total}", total)}
          </span>
          {hasMore ? (
            <button type="button" className="btn btn-ghost" style={{ width: "auto", padding: "8px 18px" }} onClick={loadMore} disabled={loadingMore}>
              {loadingMore ? t("common.loading") : t("clients.loadMore")}
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
