import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { useI18n } from "../../store/i18n";
import { CHART_COLORS, groupLabel } from "./customCharts";

// Recharts anchors axis labels for left-to-right text; under dir="rtl" the
// labels slide onto the bars. Keep the chart LTR and mirror it with
// reversed / orientation instead.
const CHART_STYLE = { direction: "ltr" };

const tick = { fill: "#8a8a8f", fontSize: 11 };

// Draws the rows returned by /api/stats/query as the chosen chart type.
export function CustomChart({ chart, rows }) {
  const t = useI18n((s) => s.t);
  // Charts are mirrored in Arabic; their text stays LTR-anchored (see CHART_STYLE).
  const isRtl = useI18n((s) => s.isRtl);

  if (!rows.length) {
    return (
      <div className="flex-center" style={{ height: "200px", color: "var(--color-muted)", fontSize: "13px", textAlign: "center" }}>
        {t("customCharts.noData")}
      </div>
    );
  }

  const valueName = t(`customCharts.metrics.${chart.metric}`);
  const data = rows.map((r, i) => ({
    name: groupLabel(t, chart.source, chart.group_by, r.key),
    value: r.value,
    color: CHART_COLORS[i % CHART_COLORS.length],
  }));
  const format = (v) => Number(v).toLocaleString();

  if (chart.chart_type === "pie") {
    return (
      <div style={{ height: "280px" }}>
        <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
          <PieChart>
            <Pie data={data} dataKey="value" nameKey="name" innerRadius={55} outerRadius={95} paddingAngle={1}>
              {data.map((d) => (
                <Cell key={d.name} fill={d.color} />
              ))}
            </Pie>
            <Tooltip formatter={(v) => [format(v), valueName]} />
            <Legend wrapperStyle={{ fontSize: "12px" }} />
          </PieChart>
        </ResponsiveContainer>
      </div>
    );
  }

  if (chart.chart_type === "line") {
    return (
      <div style={{ height: "260px" }}>
        <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
          <LineChart data={data} margin={{ top: 8, right: 12, left: 0, bottom: 0 }}>
            <CartesianGrid stroke="var(--color-line)" vertical={false} />
            <XAxis reversed={isRtl} dataKey="name" tick={tick} axisLine={false} tickLine={false} />
            <YAxis orientation={isRtl ? "right" : "left"} tick={tick} axisLine={false} tickLine={false} />
            <Tooltip formatter={(v) => [format(v), valueName]} />
            <Line type="monotone" dataKey="value" stroke={CHART_COLORS[0]} strokeWidth={2.4} dot={{ r: 4, fill: CHART_COLORS[0] }} />
          </LineChart>
        </ResponsiveContainer>
      </div>
    );
  }

  if (chart.chart_type === "hbar") {
    // One row per group, sized to fit long labels.
    return (
      <div style={{ height: `${Math.max(160, data.length * 34)}px` }}>
        <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
          <BarChart data={data} layout="vertical" margin={{ left: 8, right: 16 }}>
            <XAxis reversed={isRtl} type="number" hide />
            <YAxis orientation={isRtl ? "right" : "left"} type="category" dataKey="name" width={150} interval={0} tick={{ fill: "var(--color-ink)", fontSize: 11 }} axisLine={false} tickLine={false} />
            <Tooltip formatter={(v) => [format(v), valueName]} cursor={{ fill: "var(--color-surface)" }} />
            <Bar dataKey="value" radius={isRtl ? [6, 0, 0, 6] : [0, 6, 6, 0]} barSize={16}>
              {data.map((d) => (
                <Cell key={d.name} fill={d.color} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
    );
  }

  return (
    <div style={{ height: "260px" }}>
      <ResponsiveContainer width="100%" height="100%" style={CHART_STYLE}>
        <BarChart data={data} margin={{ top: 8, right: 12, left: 0, bottom: 0 }}>
          <CartesianGrid stroke="var(--color-line)" strokeDasharray="3 3" vertical={false} />
          <XAxis reversed={isRtl} dataKey="name" tick={tick} axisLine={false} tickLine={false} interval={0} />
          <YAxis orientation={isRtl ? "right" : "left"} tick={tick} axisLine={false} tickLine={false} />
          <Tooltip formatter={(v) => [format(v), valueName]} cursor={{ fill: "var(--color-surface)" }} />
          <Bar dataKey="value" radius={[6, 6, 0, 0]}>
            {data.map((d) => (
              <Cell key={d.name} fill={d.color} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
