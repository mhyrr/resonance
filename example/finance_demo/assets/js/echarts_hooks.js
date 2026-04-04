/**
 * ECharts hooks for Phoenix LiveView.
 * Same data contract as Resonance's ApexCharts hooks — different renderer.
 */

import * as echarts from "echarts";

function parseData(el) {
  try {
    return JSON.parse(el.dataset.chartData || "[]");
  } catch {
    return [];
  }
}

function initChart(el) {
  const existing = echarts.getInstanceByDom(el);
  if (existing) existing.dispose();
  return echarts.init(el);
}

export const EChartsLineChart = {
  mounted() {
    const data = parseData(this.el);
    const multiSeries = this.el.dataset.multiSeries === "true";
    this.chart = initChart(this.el);
    this.chart.setOption(buildLineOption(data, multiSeries));

    this.handleEvent("resonance:update-chart", ({ id, data }) => {
      if (id === this.el.id) {
        const multiSeries = this.el.dataset.multiSeries === "true";
        this.chart.setOption(buildLineOption(data, multiSeries), true);
      }
    });

    this._resizeHandler = () => this.chart.resize();
    window.addEventListener("resize", this._resizeHandler);
  },

  destroyed() {
    window.removeEventListener("resize", this._resizeHandler);
    if (this.chart) this.chart.dispose();
  },
};

export const EChartsBarChart = {
  mounted() {
    const data = parseData(this.el);
    const horizontal = this.el.dataset.orientation === "horizontal";
    this.chart = initChart(this.el);
    this.chart.setOption(buildBarOption(data, horizontal));

    this.handleEvent("resonance:update-chart", ({ id, data }) => {
      if (id === this.el.id) {
        const horizontal = this.el.dataset.orientation === "horizontal";
        this.chart.setOption(buildBarOption(data, horizontal), true);
      }
    });

    this._resizeHandler = () => this.chart.resize();
    window.addEventListener("resize", this._resizeHandler);
  },

  destroyed() {
    window.removeEventListener("resize", this._resizeHandler);
    if (this.chart) this.chart.dispose();
  },
};

export const EChartsTreemap = {
  mounted() {
    const data = parseData(this.el);
    this.chart = initChart(this.el);
    this.chart.setOption(buildTreemapOption(data));

    this.handleEvent("resonance:update-chart", ({ id, data }) => {
      if (id === this.el.id) {
        this.chart.setOption(buildTreemapOption(data), true);
      }
    });

    this._resizeHandler = () => this.chart.resize();
    window.addEventListener("resize", this._resizeHandler);
  },

  destroyed() {
    window.removeEventListener("resize", this._resizeHandler);
    if (this.chart) this.chart.dispose();
  },
};

function buildLineOption(data, multiSeries) {
  if (multiSeries) {
    const groups = {};
    const categories = [];
    for (const d of data) {
      const key = d.series || d.group || "default";
      const cat = d.period || d.label;
      if (!groups[key]) groups[key] = {};
      groups[key][cat] = d.value;
      if (!categories.includes(cat)) categories.push(cat);
    }

    const series = Object.entries(groups).map(([name, vals]) => ({
      name,
      type: "line",
      smooth: true,
      data: categories.map((c) => vals[c] || 0),
    }));

    return {
      tooltip: { trigger: "axis" },
      legend: { data: Object.keys(groups) },
      xAxis: { type: "category", data: categories },
      yAxis: { type: "value" },
      series,
      animation: true,
      animationDuration: 500,
    };
  }

  return {
    tooltip: { trigger: "axis" },
    xAxis: { type: "category", data: data.map((d) => d.period || d.label) },
    yAxis: { type: "value" },
    series: [{
      type: "line",
      smooth: true,
      data: data.map((d) => d.value),
      areaStyle: { opacity: 0.15 },
    }],
    animation: true,
    animationDuration: 500,
  };
}

function buildBarOption(data, horizontal) {
  const labels = data.map((d) => d.label || d.period);
  const values = data.map((d) => Math.abs(d.value));
  const categoryAxis = { type: "category", data: labels };
  const valueAxis = { type: "value" };

  return {
    tooltip: { trigger: "axis" },
    xAxis: horizontal ? valueAxis : categoryAxis,
    yAxis: horizontal ? categoryAxis : valueAxis,
    series: [{
      type: "bar",
      data: values,
      itemStyle: { borderRadius: horizontal ? [0, 4, 4, 0] : [4, 4, 0, 0] },
    }],
    animation: true,
    animationDuration: 500,
  };
}

function buildTreemapOption(data) {
  const hasParent = data.some((d) => d.parent);
  let treeData;

  if (hasParent) {
    const parentMap = {};
    for (const d of data) {
      const parent = d.parent || "Other";
      if (!parentMap[parent]) parentMap[parent] = { name: parent, children: [] };
      parentMap[parent].children.push({ name: d.label, value: Math.abs(d.value) });
    }
    treeData = Object.values(parentMap);
  } else {
    treeData = data.map((d) => ({ name: d.label, value: Math.abs(d.value) }));
  }

  return {
    tooltip: {
      formatter: function (info) {
        const val = (info.value / 100).toLocaleString("en-US", { style: "currency", currency: "USD" });
        return info.name + ": " + val;
      },
    },
    series: [{
      type: "treemap",
      data: treeData,
      leafDepth: 1,
      levels: [
        { itemStyle: { borderWidth: 2, borderColor: "#fff", gapWidth: 2 } },
        { itemStyle: { borderWidth: 1, borderColor: "#e5e7eb", gapWidth: 1 }, upperLabel: { show: true, height: 20 } },
      ],
      label: { show: true, formatter: "{b}" },
    }],
    animation: true,
    animationDuration: 500,
  };
}

export const EChartsPromptInput = {
  mounted() {
    this.handleEvent("resonance:set-prompt", ({ prompt }) => {
      this.el.value = prompt;
    });
  },
};

export const EChartsHooks = {
  EChartsLineChart,
  EChartsBarChart,
  EChartsTreemap,
  EChartsPromptInput,
};
