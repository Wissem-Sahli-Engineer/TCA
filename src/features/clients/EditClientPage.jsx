import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { Button } from "../../components/ui/Button";
import { BoxInput, BoxSelect, Field } from "../../components/ui/Input";
import { toast } from "../../components/ui/Toast";
import { PASSPORT_FIELDS, BUSINESS_FIELDS, CHOICE_FIELDS } from "./fields";
import { ClientChoiceFields } from "./ClientChoiceFields";
import { withToken } from "../../store/auth";
import { useI18n } from "../../store/i18n";

const ALL_FIELDS = [...PASSPORT_FIELDS, ...BUSINESS_FIELDS, ...CHOICE_FIELDS];

export function EditClientPage() {
  const t = useI18n((s) => s.t);
  const { id } = useParams();
  const navigate = useNavigate();
  const [form, setForm] = useState(null);
  const [photoFile, setPhotoFile] = useState(null);
  const [photoUrl, setPhotoUrl] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    fetch("/api/clients")
      .then((r) => (r.ok ? r.json() : []))
      .then((clients) => {
        const found = (Array.isArray(clients) ? clients : []).find((c) => String(c.id) === String(id));
        if (found) {
          setForm(Object.fromEntries(ALL_FIELDS.map((k) => [k, found[k] ?? ""])));
          setPhotoUrl(found.user_photo ? withToken(found.user_photo) : "");
        } else {
          toast(t("clients.notFound"), "err");
          navigate("/clients");
        }
      })
      .catch(() => toast(t("clients.serverError"), "err"));
  }, [id, navigate]);

  const set = (key) => (e) => setForm((f) => ({ ...f, [key]: e.target.value }));

  const onPhotoSelect = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setPhotoFile(file);
    setPhotoUrl(URL.createObjectURL(file));
  };

  const fileToDataUrl = (file) =>
    new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });

  const save = async () => {
    setBusy(true);
    try {
      const user_photo = photoFile ? await fileToDataUrl(photoFile) : "";
      const res = await fetch(`/api/clients/${id}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...form, user_photo }),
      });
      if (!res.ok) throw new Error("fail");
      toast(t("clients.updated"), "ok");
      navigate(`/clients/${id}`);
    } catch {
      toast(t("clients.updateFailed"), "err");
    } finally {
      setBusy(false);
    }
  };

  if (!form) {
    return <p style={{ color: "var(--color-muted)" }}>{t("common.loading")}</p>;
  }

  return (
    <div style={{ margin: "0 auto", maxWidth: "900px" }}>
      <Link to={`/clients/${id}`} style={{ fontSize: "13px", fontWeight: "600", color: "var(--color-brand)" }}>
        {t("clients.backToClient")}
      </Link>
      <h1 style={{ marginTop: "16px", fontSize: "28px", fontWeight: "700" }}>{t("clients.editClient")}</h1>

      <div className="card" style={{ marginTop: "20px" }}>
        <label className="upload-dropzone" style={{ display: "block" }}>
          <div style={{ fontWeight: "600", fontSize: "15px", color: "var(--color-ink)" }}>{t("clients.replacePhoto")}</div>
          <div style={{ marginTop: "4px", fontSize: "13px", color: "var(--color-muted)" }}>{t("clients.optional")}</div>
          <input type="file" accept="image/*" style={{ display: "none" }} onChange={onPhotoSelect} />
        </label>
        {photoUrl ? (
          <img src={photoUrl} alt="" className="preview-img-portrait" style={{ marginTop: "12px" }} />
        ) : null}

        <h2 style={{ marginTop: "32px", marginBottom: "8px", fontSize: "15px", fontWeight: "700", color: "var(--color-ink)" }}>
          {t("clients.passportInfo")}
        </h2>
        <div className="grid-2">
          {PASSPORT_FIELDS.map((key) => (
            <Field key={key} label={t(`clients.fields.${key}`)}>
              {key === "sex" ? (
                <BoxSelect value={form.sex} onChange={set("sex")}>
                  <option value="">{t("clients.selectValue")}</option>
                  <option value="M">M</option>
                  <option value="F">F</option>
                  <option value="X">X</option>
                </BoxSelect>
              ) : (
                <BoxInput type={key.includes("date") ? "date" : "text"} value={form[key]} onChange={set(key)} />
              )}
            </Field>
          ))}
        </div>

        <h2 style={{ marginTop: "32px", marginBottom: "8px", fontSize: "15px", fontWeight: "700", color: "var(--color-ink)" }}>
          {t("clients.contactBusiness")}
        </h2>
        <div className="grid-2">
          <ClientChoiceFields form={form} set={set} />
          {BUSINESS_FIELDS.map((key) => (
            <Field key={key} label={t(`clients.fields.${key}`)}>
              <BoxInput
                type={key === "prix_dossier" ? "number" : key === "email" ? "email" : "text"}
                value={form[key]}
                onChange={set(key)}
              />
            </Field>
          ))}
        </div>

        <div style={{ marginTop: "24px" }}>
          <Button variant="brand" loading={busy} onClick={save}>
            {t("clients.saveChanges")}
          </Button>
        </div>
      </div>
    </div>
  );
}
