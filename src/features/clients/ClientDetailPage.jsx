import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import Magnet from "../../components/ui/magnet";
import { toast } from "../../components/ui/Toast";
import { withToken } from "../../store/auth";
import { useI18n } from "../../store/i18n";
import { alertReasons, alertText, optionLabel, visaStatusOf } from "./options";

export function ClientDetailPage() {
  const t = useI18n((s) => s.t);
  const { id } = useParams();
  const navigate = useNavigate();
  const [client, setClient] = useState(null);
  const [missing, setMissing] = useState(false);
  const [files, setFiles] = useState([]);

  const loadFiles = () => {
    fetch(`/api/clients/${id}/files`)
      .then((r) => (r.ok ? r.json() : []))
      .then((data) => setFiles(Array.isArray(data) ? data : []))
      .catch(() => {});
  };

  useEffect(loadFiles, [id]);

  const removeFile = async (fileId) => {
    if (!window.confirm(t("clients.removeFile"))) return;
    await fetch(`/api/clients/${id}/files/${fileId}`, { method: "DELETE" }).catch(() => {});
    loadFiles();
  };

  const removeClient = async () => {
    if (!window.confirm(t("clients.removeConfirm"))) return;
    try {
      const res = await fetch(`/api/clients/${id}`, { method: "DELETE" });
      if (!res.ok) throw new Error("fail");
      toast(t("clients.removed"), "ok");
      navigate("/clients");
    } catch {
      toast(t("clients.removeFailed"), "err");
    }
  };

  useEffect(() => {
    let cancelled = false;
    fetch(`/api/clients/${id}`)
      .then((r) => (r.ok ? r.json() : Promise.reject()))
      .then((found) => {
        if (!cancelled) {
          setClient(found);
          setMissing(false);
        }
      })
      .catch(() => {
        if (!cancelled) setMissing(true);
      });
    return () => {
      cancelled = true;
    };
  }, [id]);

  if (missing) {
    return (
      <div style={{ margin: "0 auto", maxWidth: "900px" }}>
        <Link to="/clients" style={{ fontSize: "13px", fontWeight: "600", color: "var(--color-brand)" }}>
          {t("clients.backToClients")}
        </Link>
        <p style={{ marginTop: "24px", color: "var(--color-muted)" }}>{t("clients.notFound")}</p>
      </div>
    );
  }

  if (!client) {
    return <p style={{ color: "var(--color-muted)" }}>{t("clients.loadingFile")}</p>;
  }

  const l = (key) => t(`clients.labels.${key}`);

  const fields = [
    [l("fullName"), `${client.given_name} ${client.surname}`],
    [l("dateOfBirth"), client.date_of_birth],
    [l("nationality"), client.nationality],
    [l("passportNumber"), client.passport_number],
    [l("expiry"), client.date_of_expiry],
    [l("placeOfBirth"), client.place_of_birth],
    [l("issuedBy"), client.issued_by],
    [l("phone"), client.phone],
    [l("email"), client.email],
    [l("entreprise"), client.entreprise_name],
    [l("codeFiscal"), client.code_fiscal],
    [l("category"), optionLabel(t, "category", client.category)],
    ...(client.category === "fair" ? [[l("fairEmail"), client.fair_email]] : []),
    [l("visaStatus"), optionLabel(t, "visa", visaStatusOf(client))],
    [
      l("visaType"),
      client.visa_type === "other" && client.visa_type_other
        ? `${optionLabel(t, "visaType", "other")}: ${client.visa_type_other}`
        : optionLabel(t, "visaType", client.visa_type),
    ],
    [l("prixDossier"), client.prix_dossier],
    [l("paiementType"), optionLabel(t, "paymentMethod", client.paiement_type)],
    [l("paymentState"), optionLabel(t, "payment", client.payment_state)],
    [l("currency"), optionLabel(t, "currencies", client.currency)],
    [l("hasFlight"), client.has_flight ? t("common.yes") : t("common.no")],
    ...(client.has_flight ? [[l("flightDate"), client.flight_date]] : []),
    [l("destination"), client.destination],
    ...(client.category === "reservation"
      ? [
          ...(client.has_flight ? [[l("airlineName"), client.airline_name]] : []),
          [l("hotelReservation"), client.hotel_reservation ? t("common.yes") : t("common.no")],
          ...(client.hotel_reservation ? [[l("hotelName"), client.hotel_name]] : []),
          [l("duration"), client.duration],
          [l("reservationAmount"), client.reservation_amount],
        ]
      : []),
    [l("addedBy"), client.created_by],
  ];

  return (
    <div style={{ margin: "0 auto", maxWidth: "1100px" }}>
      <div className="flex-between">
        <Link to="/clients" style={{ fontSize: "13px", fontWeight: "600", color: "var(--color-brand)" }}>
          {t("clients.backToClients")}
        </Link>
        <div style={{ display: "flex", gap: "10px" }}>
          <Magnet padding={26} magnetStrength={14}>
            <Link
              to={`/clients/${id}/edit`}
              className="btn btn-brand"
              style={{ width: "auto", padding: "8px 16px", fontSize: "13px" }}
            >
              {t("clients.editClient")}
            </Link>
          </Magnet>
          <Magnet padding={26} magnetStrength={14}>
            <button
              type="button"
              onClick={removeClient}
              className="btn btn-danger"
              style={{ width: "auto", padding: "8px 16px", fontSize: "13px" }}
            >
              {t("clients.removeClient")}
            </button>
          </Magnet>
        </div>
      </div>
      <div className="grid-12" style={{ marginTop: "24px" }}>
        <div className="col-4">
          <div className="card" style={{ padding: 0, overflow: "hidden" }}>
            {client.user_photo ? (
              <img
                src={withToken(client.user_photo)}
                alt={t("clients.passportPortrait")}
                style={{ height: "280px", width: "100%", objectFit: "cover" }}
              />
            ) : (
              <div
                className="flex-center"
                style={{ height: "280px", backgroundColor: "var(--color-surface)", color: "var(--color-muted)" }}
              >
                {t("clients.noFiles")}
              </div>
            )}
            <div style={{ padding: "20px" }}>
              <p style={{ fontSize: "12px", fontWeight: "600", textTransform: "uppercase", letterSpacing: "0.14em", color: "var(--color-muted)" }}>
                {l("passportNumber")}
              </p>
              <h1 style={{ marginTop: "4px", fontSize: "22px", fontWeight: "700", color: "var(--color-ink)" }}>
                {client.given_name} {client.surname}
              </h1>
              <p style={{ marginTop: "4px", fontFamily: "monospace", fontSize: "13px", color: "var(--color-muted)" }}>
                {client.passport_number}
              </p>
              {alertReasons(client).map((r) => (
                <p key={r.id} style={{ marginTop: "8px", fontSize: "13px", fontWeight: "600", color: "var(--color-danger)" }}>
                  ⚠ {alertText(t, r)}
                </p>
              ))}
            </div>
          </div>
        </div>

        <div className="col-8" style={{ display: "flex", flexDirection: "column", gap: "24px" }}>
          <div className="card" style={{ padding: "24px" }}>
            <h2 style={{ marginBottom: "16px", fontSize: "16px", fontWeight: "700" }}>{t("clients.personalInfo")}</h2>
            <dl className="grid-2" style={{ gap: "16px 24px" }}>
              {fields.map(([k, v]) => (
                <div key={k} style={{ borderBottom: "1px solid var(--color-line)", paddingBottom: "8px" }}>
                  <dt style={{ fontSize: "12px", fontWeight: "600", color: "var(--color-muted)" }}>{k}</dt>
                  <dd style={{ marginTop: "4px", fontSize: "14px", fontWeight: "500", color: "var(--color-ink)" }}>
                    {v || "—"}
                  </dd>
                </div>
              ))}
            </dl>
          </div>

          <div className="card" style={{ padding: "24px" }}>
            <h2 style={{ marginBottom: "12px", fontSize: "16px", fontWeight: "700" }}>{t("clients.documents")}</h2>
            {files.length === 0 ? (
              <p style={{ fontSize: "13px", color: "var(--color-muted)" }}>{t("clients.noFiles")}</p>
            ) : (
              <ul style={{ listStyle: "none", display: "flex", flexDirection: "column", gap: "8px", fontSize: "14px" }}>
                {files.map((f) => (
                  <li key={f.id} className="flex-between" style={{ borderBottom: "1px solid var(--color-line)", padding: "8px 0" }}>
                    <a href={withToken(f.url)} target="_blank" rel="noreferrer" style={{ color: "var(--color-brand)" }}>
                      {f.filename}
                    </a>
                    <button type="button" onClick={() => removeFile(f.id)} style={{ color: "var(--color-danger)", fontSize: "12px", fontWeight: "600" }}>
                      {t("common.remove")}
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
