import { useTheme } from "../store/theme";
import { IconSun, IconMoon } from "./ui/Icons";
import Magnet from "./ui/magnet";
import { useI18n } from "../store/i18n";

export function ThemeToggle() {
  const theme = useTheme((s) => s.theme);
  const toggle = useTheme((s) => s.toggle);
  const isDark = theme === "dark";
  const t = useI18n((s) => s.t);

  return (
    <Magnet padding={22} magnetStrength={14}>
      <button
        type="button"
        onClick={toggle}
        className="icon-btn"
        aria-label={t("shell.toggleTheme")}
        title={t("shell.toggleTheme")}
      >
        {isDark ? <IconMoon size={17} /> : <IconSun size={17} />}
      </button>
    </Magnet>
  );
}
