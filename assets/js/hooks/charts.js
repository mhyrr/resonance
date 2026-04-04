/**
 * Resonance chart hooks for Phoenix LiveView.
 *
 * These hooks use ApexCharts for rendering. The consuming app must
 * include ApexCharts in its JS bundle:
 *
 *   npm install apexcharts
 *
 * Then register these hooks in your LiveSocket:
 *
 *   import { ResonanceHooks } from "resonance/hooks/charts"
 *   let liveSocket = new LiveSocket("/live", Socket, {
 *     hooks: { ...ResonanceHooks }
 *   })
 */

function parseData(el) {
  try {
    return JSON.parse(el.dataset.chartData || "[]");
  } catch {
    return [];
  }
}

export const ResonanceLineChart = {
  mounted() {
    const data = parseData(this.el);
    const multiSeries = this.el.dataset.multiSeries === "true";
    const title = this.el.dataset.title || "";

    const series = multiSeries
      ? buildMultiSeries(data)
      : [{ name: title, data: data.map((d) => d.value) }];

    const categories = multiSeries
      ? [...new Set(data.map((d) => d.period || d.label))]
      : data.map((d) => d.period || d.label);

    this.chart = new ApexCharts(this.el, {
      chart: { type: "line", height: 300, toolbar: { show: false } },
      series: series,
      xaxis: { categories: categories },
      stroke: { curve: "smooth", width: 2 },
      title: { text: "", style: { fontSize: "14px" } },
    });
    this.chart.render();
  },

  updated() {
    const data = parseData(this.el);
    const multiSeries = this.el.dataset.multiSeries === "true";

    const series = multiSeries
      ? buildMultiSeries(data)
      : [
          {
            name: this.el.dataset.title || "",
            data: data.map((d) => d.value),
          },
        ];

    this.chart.updateSeries(series);
  },

  destroyed() {
    if (this.chart) this.chart.destroy();
  },
};

export const ResonanceBarChart = {
  mounted() {
    const data = parseData(this.el);
    const horizontal = this.el.dataset.orientation === "horizontal";
    const stacked = this.el.dataset.stacked === "true";
    const title = this.el.dataset.title || "";

    this.chart = new ApexCharts(this.el, {
      chart: {
        type: "bar",
        height: 300,
        stacked: stacked,
        toolbar: { show: false },
      },
      plotOptions: { bar: { horizontal: horizontal } },
      series: [{ name: title, data: data.map((d) => d.value) }],
      xaxis: { categories: data.map((d) => d.label || d.period) },
      title: { text: "", style: { fontSize: "14px" } },
    });
    this.chart.render();
  },

  updated() {
    const data = parseData(this.el);
    this.chart.updateSeries([
      { name: this.el.dataset.title || "", data: data.map((d) => d.value) },
    ]);
  },

  destroyed() {
    if (this.chart) this.chart.destroy();
  },
};

export const ResonancePieChart = {
  mounted() {
    const data = parseData(this.el);
    const donut = this.el.dataset.donut === "true";
    const title = this.el.dataset.title || "";

    this.chart = new ApexCharts(this.el, {
      chart: { type: donut ? "donut" : "pie", height: 300 },
      series: data.map((d) => d.value),
      labels: data.map((d) => d.label),
      title: { text: "", style: { fontSize: "14px" } },
    });
    this.chart.render();
  },

  updated() {
    const data = parseData(this.el);
    this.chart.updateSeries(data.map((d) => d.value));
  },

  destroyed() {
    if (this.chart) this.chart.destroy();
  },
};

function buildMultiSeries(data) {
  const seriesMap = {};
  for (const d of data) {
    const key = d.series || d.group || "default";
    if (!seriesMap[key]) seriesMap[key] = { name: key, data: [] };
    seriesMap[key].data.push(d.value);
  }
  return Object.values(seriesMap);
}

export const ResonanceHooks = {
  ResonanceLineChart,
  ResonanceBarChart,
  ResonancePieChart,
};
