import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Button } from "../../components/ui/Button";
import { BoxInput, BoxSelect, Field } from "../../components/ui/Input";
import { toast } from "../../components/ui/Toast";
import { PASSPORT_FIELDS, BUSINESS_FIELDS, CHOICE_FIELDS } from "./fields";
import { ClientChoiceFields } from "./ClientChoiceFields";
import { useI18n } from "../../store/i18n";

const EMPTY = {
  ...Object.fromEntries([...PASSPORT_FIELDS, ...BUSINESS_FIELDS, ...CHOICE_FIELDS].map((k) => [k, ""])),
  category: "normal",
  visa_status: "new",
  has_flight: false,
  hotel_reservation: false,
};

export function AddClientPage() {
  const t = useI18n((s) => s.t);
  const navigate = useNavigate();
  const [form, setForm] = useState(EMPTY);

  const [passportFile, setPassportFile] = useState(null);
  const [passportUrl, setPassportUrl] = useState("");
  const [extracting, setExtracting] = useState(false);

  const [photoFile, setPhotoFile] = useState(null);
  const [photoUrl, setPhotoUrl] = useState("");

  const [otherFiles, setOtherFiles] = useState([]);

  const [busy, setBusy] = useState(false);

  const set = (key) => (e) => setForm((f) => ({ ...f, [key]: e.target.value }));

  const onPassportSelect = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setPassportFile(file);
    setPassportUrl(URL.createObjectURL(file));
  };

  const extractViaAi = async () => {
    if (!passportFile) {
      toast(t("clients.uploadFirst"), "err");
      return;
    }
    setExtracting(true);
    const body = new FormData();
    body.append("file", passportFile);
    try {
      const res = await fetch("/api/extract", { method: "POST", body });
      if (!res.ok) throw new Error("fail");
      const data = await res.json();
      setForm((f) => ({ ...f, ...Object.fromEntries(PASSPORT_FIELDS.map((k) => [k, data[k] || ""])) }));
      toast(t("clients.extracted"), "ok");
    } catch {
      toast(t("clients.extractFailed"), "err");
    } finally {
      setExtracting(false);
    }
  };

  const onPhotoSelect = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setPhotoFile(file);
    setPhotoUrl(URL.createObjectURL(file));
  };

  const onOtherFilesSelect = (e) => {
    const files = Array.from(e.target.files || []);
    setOtherFiles((f) => [...f, ...files]);
  };

  const removeOtherFile = (index) => {
    setOtherFiles((files) => files.filter((_, i) => i !== index));
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

      const res = await fetch("/api/clients", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...form, user_photo }),
      });
      if (!res.ok) throw new Error("fail");
      const { client } = await res.json();

      const filesToUpload = [...(passportFile ? [passportFile] : []), ...otherFiles];
      if (filesToUpload.length) {
        const body = new FormData();
        filesToUpload.forEach((f) => body.append("files", f));
        await fetch(`/api/clients/${client.id}/files`, { method: "POST", body }).catch(() => {});
      }

      toast(t("clients.saved"), "ok");
      navigate(`/clients/${client.id}`);
    } catch {
      toast(t("clients.saveFailed"), "err");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div style={{ margin: "0 auto", maxWidth: "900px" }}>
      <Link to="/clients" style={{ fontSize: "13px", fontWeight: "600", color: "var(--color-brand)" }}>
        {t("clients.backToClients")}
      </Link>
      <h1 style={{ marginTop: "16px", fontSize: "28px", fontWeight: "700" }}>{t("clients.addClient")}</h1>
      <p style={{ marginBottom: "24px", fontSize: "14px", color: "var(--color-muted)" }}>
        {t("clients.addClientSubtitle")}
      </p>

      <div className="card">
        <div className="grid-2">
          <div>
            <label className="upload-dropzone" style={{ display: "block" }}>
              <div style={{ fontWeight: "600", fontSize: "15px", color: "var(--color-ink)" }}>{t("clients.uploadPassport")}</div>
              <div style={{ marginTop: "4px", fontSize: "13px", color: "var(--color-muted)" }}>
                {t("clients.savedWithFiles")}
              </div>
              <input type="file" accept="image/*" style={{ display: "none" }} onChange={onPassportSelect} />
            </label>
            {passportUrl ? (
              <img
                src={passportUrl}
                alt=""
                className="preview-img-passport"
                style={{ marginTop: "12px" }}
              />
            ) : null}
            <div style={{ marginTop: "12px" }}>
              <Button variant="brand" loading={extracting} onClick={extractViaAi} disabled={!passportFile}>
                {t("clients.extractViaAi")}
              </Button>
            </div>
          </div>

          <div>
            <label className="upload-dropzone" style={{ display: "block" }}>
              <div style={{ fontWeight: "600", fontSize: "15px", color: "var(--color-ink)" }}>{t("clients.uploadPhoto")}</div>
              <div style={{ marginTop: "4px", fontSize: "13px", color: "var(--color-muted)" }}>
                {t("clients.manualUpload")}
              </div>
              <input type="file" accept="image/*" style={{ display: "none" }} onChange={onPhotoSelect} />
            </label>
            {photoUrl ? (
              <img src={photoUrl} alt="" className="preview-img-portrait" style={{ marginTop: "12px" }} />
            ) : null}
          </div>
        </div>

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
                <BoxInput
                  type={key.includes("date") ? "date" : "text"}
                  value={form[key]}
                  onChange={set(key)}
                />
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

        <h2 style={{ marginTop: "32px", marginBottom: "8px", fontSize: "15px", fontWeight: "700", color: "var(--color-ink)" }}>
          {t("clients.otherFiles")}
        </h2>
        <label className="upload-dropzone" style={{ display: "block" }}>
          <div style={{ fontWeight: "600", fontSize: "14px", color: "var(--color-ink)" }}>{t("clients.uploadOtherDocs")}</div>
          <div style={{ marginTop: "4px", fontSize: "13px", color: "var(--color-muted)" }}>
            {t("clients.otherDocsHint")}
          </div>
          <input type="file" multiple style={{ display: "none" }} onChange={onOtherFilesSelect} />
        </label>
        {otherFiles.length ? (
          <ul style={{ marginTop: "12px", display: "flex", flexDirection: "column", gap: "6px" }}>
            {otherFiles.map((f, i) => (
              <li
                key={i}
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  fontSize: "13px",
                  color: "var(--color-ink)",
                  backgroundColor: "var(--color-surface)",
                  borderRadius: "8px",
                  padding: "8px 12px",
                }}
              >
                <span>{f.name}</span>
                <button
                  type="button"
                  onClick={() => removeOtherFile(i)}
                  style={{ color: "var(--color-danger)", fontWeight: "600" }}
                >
                  {t("common.remove")}
                </button>
              </li>
            ))}
          </ul>
        ) : null}

        <div style={{ marginTop: "24px" }}>
          <Button variant="brand" loading={busy} onClick={save}>
            {t("clients.saveToDatabase")}
          </Button>
        </div>
      </div>
    </div>
  );
}
