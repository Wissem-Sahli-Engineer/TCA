import { useEffect, useRef, useState } from "react";
import { IconBell } from "./ui/Icons";
import Magnet from "./ui/magnet";
import { useI18n } from "../store/i18n";
import { alertReasons, alertText } from "../features/clients/options";

const COUNTRIES = [
  { id: "tunisia", currency: "TND" },
  { id: "libya", currency: "LYD" },
];

export function NotificationBell() {
  const t = useI18n((s) => s.t);
  const [open, setOpen] = useState(false);
  const [alertClients, setAlertClients] = useState([]);
  const [treasury, setTreasury] = useState([]);
  const boxRef = useRef(null);

  const load = () => {
    fetch("/api/clients?tab=alert&limit=50")
      .then((r) => (r.ok ? r.json() : []))
      .then((clients) => setAlertClients(Array.isArray(clients) ? clients : []))
      .catch(() => setAlertClients([]));

    Promise.all(
      COUNTRIES.map((c) =>
        fetch(`/api/treasury?country=${c.id}`)
          .then((r) => (r.ok ? r.json() : null))
          .then((data) => ({ ...c, net: data?.current_month?.net ?? 0 }))
          .catch(() => ({ ...c, net: 0 }))
      )
    ).then(setTreasury);
  };

  useEffect(() => {
    load();
    const id = setInterval(load, 60000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    if (!open) return;
    const onClickOutside = (e) => {
      if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener("mousedown", onClickOutside);
    return () => document.removeEventListener("mousedown", onClickOutside);
  }, [open]);

  const hasNegative = treasury.some((tr) => tr.net < 0);
  const count = alertClients.length + treasury.filter((tr) => tr.net < 0).length;

  return (
    <div style={{ position: "relative" }} ref={boxRef}>
      <Magnet padding={22} magnetStrength={14}>
        <button
          type="button"
          className="icon-btn"
          aria-label={t("header.notifications")}
          onClick={() => setOpen((o) => !o)}
        >
          <IconBell />
        </button>
      </Magnet>
      {count > 0 ? (
        <span
          style={{
            position: "absolute",
            right: "8px",
            top: "8px",
            width: "6px",
            height: "6px",
            borderRadius: "50%",
            backgroundColor: hasNegative ? "var(--color-danger)" : "var(--color-accent-orange)",
          }}
        />
      ) : null}

      {open ? (
        <div
          className="card"
          style={{
            position: "absolute",
            top: "calc(100% + 8px)",
            insetInlineEnd: 0,
            width: "min(320px, calc(100vw - 32px))",
            padding: "16px",
            zIndex: 50,
            boxShadow: "var(--shadow-login)",
          }}
        >
          <p style={{ fontSize: "11px", fontWeight: "700", textTransform: "uppercase", letterSpacing: "0.1em", color: "var(--color-muted)", marginBottom: "10px" }}>
            {t("notifications.treasury")}
          </p>
          {treasury.map((tr) => (
            <div key={tr.id} className="flex-between" style={{ marginBottom: "6px" }}>
              <span style={{ fontSize: "13px" }}>{t(`countries.${tr.id}`)}</span>
              <span style={{ fontSize: "13px", fontWeight: "700", color: tr.net < 0 ? "var(--color-danger)" : "var(--color-success)" }}>
                {tr.currency} {tr.net.toLocaleString()}{tr.net < 0 ? " ⚠" : ""}
              </span>
            </div>
          ))}

          <p style={{ fontSize: "11px", fontWeight: "700", textTransform: "uppercase", letterSpacing: "0.1em", color: "var(--color-muted)", margin: "14px 0 10px" }}>
            {t("notifications.clientsInAlert")}
          </p>
          {alertClients.length === 0 ? (
            <p style={{ fontSize: "13px", color: "var(--color-muted)" }}>{t("notifications.noAlerts")}</p>
          ) : (
            alertClients.map((c) => (
              <div key={c.id} style={{ fontSize: "13px", padding: "4px 0" }}>
                {c.given_name} {c.surname} — <span style={{ color: "var(--color-danger)" }}>{alertReasons(c).map((r) => alertText(t, r)).join(" · ")}</span>
              </div>
            ))
          )}
        </div>
      ) : null}
    </div>
  );
}
