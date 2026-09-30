import { BoxInput, BoxSelect, Field } from "../../components/ui/Input";
import { useI18n } from "../../store/i18n";
import {
  CLIENT_CATEGORIES,
  CURRENCIES,
  PAYMENT_METHODS,
  PAYMENT_STATES,
  VISA_STATUSES,
  VISA_TYPES,
  optionLabel,
} from "./options";

const fullRow = { gridColumn: "1 / -1", marginTop: "12px", fontSize: "14px", fontWeight: "700", color: "var(--color-ink)" };

// The pick-list, travel and reservation fields shared by the Add and Edit
// client forms. Fields that only apply in some cases (fair email, the
// free-text visa type, flight date, reservation details, hotel name) are
// only shown then — the backend also clears them otherwise.
export function ClientChoiceFields({ form, set }) {
  const t = useI18n((s) => s.t);
  const label = (key) => t(`clients.fields.${key}`);

  const select = (key, namespace, ids, { allowEmpty = true } = {}) => (
    <Field label={label(key)}>
      <BoxSelect value={form[key] || ""} onChange={set(key)}>
        {allowEmpty ? <option value="">{t("clients.selectValue")}</option> : null}
        {ids.map((id) => (
          <option key={id} value={id}>
            {optionLabel(t, namespace, id)}
          </option>
        ))}
      </BoxSelect>
    </Field>
  );

  const yesNo = (key) => (
    <Field label={label(key)}>
      <BoxSelect
        value={form[key] ? "yes" : "no"}
        onChange={(e) => set(key)({ target: { value: e.target.value === "yes" } })}
      >
        <option value="no">{t("common.no")}</option>
        <option value="yes">{t("common.yes")}</option>
      </BoxSelect>
    </Field>
  );

  const input = (key, type = "text") => (
    <Field label={label(key)}>
      <BoxInput type={type} value={form[key] ?? ""} onChange={set(key)} />
    </Field>
  );

  const isReservation = form.category === "reservation";

  return (
    <>
      {select("category", "category", CLIENT_CATEGORIES, { allowEmpty: false })}
      {form.category === "fair" ? input("fair_email", "email") : null}
      <Field label={t("clients.visaStatus")}>
        <BoxSelect value={form.visa_status || ""} onChange={set("visa_status")}>
          <option value="">{t("clients.selectValue")}</option>
          {VISA_STATUSES.map((s) => (
            <option key={s.id} value={s.id}>
              {optionLabel(t, "visa", s.id)}
            </option>
          ))}
        </BoxSelect>
      </Field>
      {select("visa_type", "visaType", VISA_TYPES)}
      {form.visa_type === "other" ? input("visa_type_other") : null}
      {select("paiement_type", "paymentMethod", PAYMENT_METHODS)}
      {select("payment_state", "payment", PAYMENT_STATES.map((s) => s.id))}
      {select("currency", "currencies", CURRENCIES)}

      <h3 style={fullRow}>{t("clients.travel")}</h3>
      {yesNo("has_flight")}
      {form.has_flight ? input("flight_date", "date") : null}
      {input("destination")}

      {isReservation ? (
        <>
          <h3 style={fullRow}>{t("clients.reservationDetails")}</h3>
          {form.has_flight ? input("airline_name") : null}
          {yesNo("hotel_reservation")}
          {form.hotel_reservation ? input("hotel_name") : null}
          {input("duration")}
          {input("reservation_amount", "number")}
        </>
      ) : null}
    </>
  );
}
