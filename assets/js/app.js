// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/ksef_hub"
import topbar from "../vendor/topbar"
import Chart from "../vendor/chart.js"

// Chart color palettes
const DONUT_COLORS = [
  "rgba(59,130,246,0.7)",   // blue
  "rgba(251,191,36,0.7)",   // amber
  "rgba(34,197,94,0.7)",    // green
  "rgba(239,68,68,0.7)",    // red
  "rgba(168,85,247,0.7)",   // purple
  "rgba(236,72,153,0.7)",   // pink
  "rgba(20,184,166,0.7)",   // teal
  "rgba(249,115,22,0.7)",   // orange
  "rgba(107,114,128,0.7)",  // gray
  "rgba(99,102,241,0.7)",   // indigo
  "rgba(14,165,233,0.7)",   // sky
  "rgba(132,204,22,0.7)",   // lime
  "rgba(244,63,94,0.7)",    // rose
  "rgba(217,70,239,0.7)",   // fuchsia
  "rgba(245,158,11,0.7)",   // yellow
]

function showEmptyState(el) {
  const canvas = el.querySelector("canvas")
  canvas.style.display = "none"
  let msg = el.querySelector(".chart-empty")
  if (!msg) {
    msg = document.createElement("div")
    msg.className = "chart-empty flex items-center justify-center h-full text-sm text-muted-foreground"
    msg.textContent = "No data for selected period"
    el.appendChild(msg)
  }
  msg.style.display = ""
}

function hideEmptyState(el) {
  const canvas = el.querySelector("canvas")
  canvas.style.display = ""
  const msg = el.querySelector(".chart-empty")
  if (msg) msg.style.display = "none"
}

const ExpenseBarChart = {
  mounted() {
    const ctx = this.el.querySelector("canvas").getContext("2d")
    this.chart = new Chart(ctx, {
      type: "bar",
      data: {
        labels: [],
        datasets: [{
          label: "Net Expenses",
          data: [],
          backgroundColor: "rgba(251, 191, 36, 0.7)",
          borderColor: "rgb(251, 191, 36)",
          borderWidth: 1,
        }],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { display: false } },
        scales: {
          y: { beginAtZero: true, ticks: { callback: v => v.toLocaleString("pl-PL") } },
          x: { ticks: { maxRotation: 45 } },
        },
      },
    })
    this.handleEvent("expense-bar-data", ({ labels, values }) => {
      if (values.length === 0) {
        showEmptyState(this.el)
      } else {
        hideEmptyState(this.el)
      }
      this.chart.data.labels = labels
      this.chart.data.datasets[0].data = values
      this.chart.update()
    })
  },
  destroyed() {
    if (this.chart) this.chart.destroy()
  },
}

const CategoryDonutChart = {
  mounted() {
    const ctx = this.el.querySelector("canvas").getContext("2d")
    this.chart = new Chart(ctx, {
      type: "doughnut",
      data: {
        labels: [],
        datasets: [{ data: [], backgroundColor: DONUT_COLORS }],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: "right",
            labels: { boxWidth: 12, padding: 8, font: { size: 11 } },
          },
        },
      },
    })
    this.handleEvent("category-donut-data", ({ labels, values }) => {
      if (values.length === 0) {
        showEmptyState(this.el)
      } else {
        hideEmptyState(this.el)
      }
      this.chart.data.labels = labels
      this.chart.data.datasets[0].data = values
      this.chart.update()
    })
  },
  destroyed() {
    if (this.chart) this.chart.destroy()
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ExpenseBarChart, CategoryDonutChart},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Copy to clipboard via push_event from LiveView
window.addEventListener("phx:copy_to_clipboard", (event) => {
  if (navigator.clipboard && event.detail.text) {
    navigator.clipboard.writeText(event.detail.text)
  }
})

// Download file via push_event from LiveView (keeps LiveView alive)
window.addEventListener("phx:download", (event) => {
  if (event.detail.url) {
    window.open(event.detail.url, "_blank")
  }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

