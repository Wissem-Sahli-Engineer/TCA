import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { IconSearch } from "./ui/Icons";
import { useUi } from "../store/ui";
import { useI18n } from "../store/i18n";

const COUNTRIES = ["tunisia", "libya"];

export function GlobalSearch() {
  const navigate = useNavigate();
  const t = useI18n((s) => s.t);
  const search = useUi((s) => s.search);
  const setSearch = useUi((s) => s.setSearch);
  const [open, setOpen] = useState(false);
  const [clients, setClients] = useState([]);
  const [invoices, setInvoices] = useState([]);
  const boxRef = useRef(null);

  useEffect(() => {
    const q = search.trim().toLowerCase();
    if (q.length < 2) {
      setClients([]);
      setInvoices([]);
      return;
    }

    // The server does the searching; only a handful of matches are ever downloaded.
    // Debounced, and a slow answer for an older search can't replace a newer one.
    let stale = false;
    const timer = setTimeout(() => {
      const term = encodeURIComponent(q);
      fetch(`/api/clients?q=${term}&limit=6`)
        .then((r) => (r.ok ? r.json() : []))
        .then((data) => !stale && setClients(Array.isArray(data) ? data : []))
        .catch(() => !stale && setClients([]));

      Promise.all(
        COUNTRIES.map((c) => fetch(`/api/invoices?country=${c}&q=${term}&limit=6`).then((r) => (r.ok ? r.json() : [])))
      )
        .then((results) => !stale && setInvoices(results.flat().slice(0, 6)))
        .catch(() => !stale && setInvoices([]));
    }, 250);
    return () => {
      stale = true;
      clearTimeout(timer);
    };
  }, [search]);

  useEffect(() => {
    if (!open) return;
    const onClickOutside = (e) => {
      if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener("mousedown", onClickOutside);
    return () => document.removeEventListener("mousedown", onClickOutside);
  }, [open]);

  const goTo = (path) => {
    setOpen(false);
    setSearch("");
    navigate(path);
  };

  const hasResults = clients.length > 0 || invoices.length > 0;

  return (
    <div style={{ position: "relative" }} ref={boxRef}>
      <label className="search-bar">
        <span className="search-bar-icon">
          <IconSearch size={16} />
        </span>
        <input
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          placeholder={t("header.search")}
          className="search-bar-input"
        />
      </label>

      {open && search.trim().length >= 2 ? (
        <div
          className="card"
          style={{
            position: "absolute",
            top: "calc(100% + 8px)",
            left: 0,
            width: "360px",
            padding: "12px",
            zIndex: 50,
            boxShadow: "var(--shadow-login)",
          }}
        >
          {!hasResults ? (
            <p style={{ fontSize: "13px", color: "var(--color-muted)", padding: "8px" }}>{t("search.noMatches")}</p>
          ) : (
            <>
              {clients.length > 0 ? (
                <div style={{ marginBottom: invoices.length ? "10px" : 0 }}>
                  <p style={{ fontSize: "11px", fontWeight: "700", textTransform: "uppercase", letterSpacing: "0.1em", color: "var(--color-muted)", padding: "4px 8px" }}>
                    {t("search.clients")}
                  </p>
                  {clients.map((c) => (
                    <button
                      key={c.id}
                      type="button"
                      onClick={() => goTo(`/clients/${c.id}`)}
                      style={{
                        display: "block", width: "100%", textAlign: "left", padding: "8px",
                        borderRadius: "8px", fontSize: "13px", color: "var(--color-ink)",
                      }}
                      onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = "var(--color-surface)")}
                      onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = "transparent")}
                    >
                      {c.given_name} {c.surname} <span style={{ color: "var(--color-muted)" }}>· {c.passport_number}</span>
                    </button>
                  ))}
                </div>
              ) : null}

              {invoices.length > 0 ? (
                <div>
                  <p style={{ fontSize: "11px", fontWeight: "700", textTransform: "uppercase", letterSpacing: "0.1em", color: "var(--color-muted)", padding: "4px 8px" }}>
                    {t("search.invoices")}
                  </p>
                  {invoices.map((inv) => (
                    <button
                      key={inv.id}
                      type="button"
                      onClick={() => goTo(`/accounting/${inv.country}`)}
                      style={{
                        display: "block", width: "100%", textAlign: "left", padding: "8px",
                        borderRadius: "8px", fontSize: "13px", color: "var(--color-ink)",
                      }}
                      onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = "var(--color-surface)")}
                      onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = "transparent")}
                    >
                      {inv.number} <span style={{ color: "var(--color-muted)" }}>· {inv.client_name}</span>
                    </button>
                  ))}
                </div>
              ) : null}
            </>
          )}
        </div>
      ) : null}
    </div>
  );
}
