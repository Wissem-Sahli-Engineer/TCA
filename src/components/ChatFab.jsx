import { IconChat } from "./ui/Icons";
import { useUi } from "../store/ui";
import Magnet from "./ui/magnet";
import { useI18n } from "../store/i18n";

export function ChatFab() {
  const toggleChatbot = useUi((s) => s.toggleChatbot);
  const t = useI18n((s) => s.t);
  return (
    <div className="chat-fab-wrap">
      <Magnet padding={36} magnetStrength={12}>
        <button
          type="button"
          onClick={toggleChatbot}
          className="chat-fab"
          aria-label={t("shell.openAssistant")}
        >
          <IconChat size={22} />
        </button>
      </Magnet>
    </div>
  );
}
