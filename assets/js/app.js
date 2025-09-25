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
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/wordgo";
import topbar from "../vendor/topbar";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const hooks = {
  ...colocatedHooks,
  AutoFocusSelect: {
    focusAndSelect() {
      const el = this.el;
      if (!el) return;
      requestAnimationFrame(() => {
        if (typeof el.focus === "function") el.focus();
        if (typeof el.select === "function") el.select();
        if (typeof el.setSelectionRange === "function")
          el.setSelectionRange(0, el.value?.length || 0);
      });
    },
    mounted() {
      this.focusAndSelect();
    },
    updated() {
      this.focusAndSelect();
    },
  },
  TimerCountdown: {
    parseEndsAt() {
      const { endsAt, remainingMs } = this.el.dataset || {};
      if (remainingMs && !isNaN(parseInt(remainingMs))) {
        return Date.now() + parseInt(remainingMs);
      }
      if (endsAt) {
        const t = Date.parse(endsAt);
        if (!isNaN(t)) return t;
      }
      return null;
    },
    format(ms) {
      const clamped = Math.max(0, ms);
      const totalSec = Math.floor(clamped / 1000);
      const m = Math.floor(totalSec / 60);
      const s = totalSec % 60;
      const pad = (n) => (n < 10 ? "0" + n : "" + n);
      return `${pad(m)}:${pad(s)}`;
    },
    render(msLeft) {
      const winner = this.getWinner();
      if (winner) {
        this.el.textContent = `Winner: ${winner}`;
        if (!this.hasCelebrated) {
          this.hasCelebrated = true;
          this.celebrate(winner);
        }
        return;
      }
      if (msLeft <= 0) {
        this.el.textContent = "00:00";
      } else {
        this.el.textContent = this.format(msLeft);
      }
    },
    tick() {
      if (!this.endsAt) {
        this.stop();
        return;
      }
      const now = Date.now();
      const msLeft = this.endsAt - now;
      this.render(msLeft);
      if (msLeft <= 0) this.stop();
    },
    start() {
      this.stop();
      this.endsAt = this.parseEndsAt();
      this.tick();
      if (this.endsAt) {
        this.timer = setInterval(() => this.tick(), 1000);
      }
    },
    stop() {
      if (this.timer) {
        clearInterval(this.timer);
        this.timer = null;
      }
    },
    mounted() {
      this.start();
    },
    updated() {
      this.start();
    },
    destroyed() {
      this.stop();
    },
    getWinner() {
      const v = this.el.dataset?.winner;
      if (!v || v === "false" || v === "null" || v === "undefined") return null;
      return v;
    },
    celebrate(winner) {
      this.ensureConfetti().then((confetti) => {
        if (!confetti) return;
        // burst sequence
        const duration = 1800;
        const end = Date.now() + duration;
        const colors = ["#a3e635", "#f59e0b", "#f472b6", "#60a5fa", "#34d399"];
        const frame = () => {
          confetti({
            particleCount: 3,
            startVelocity: 40,
            spread: 70,
            ticks: 200,
            origin: { x: Math.random(), y: Math.random() - 0.2 },
            colors,
            shapes: ["square", "circle"],
          });
          if (Date.now() < end) requestAnimationFrame(frame);
        };
        frame();
      });
    },
    ensureConfetti() {
      if (window.confetti) return Promise.resolve(window.confetti);
      return new Promise((resolve) => {
        const script = document.createElement("script");
        script.src =
          "https://cdn.jsdelivr.net/npm/canvas-confetti@1.9.3/dist/confetti.browser.min.js";
        script.async = true;
        script.onload = () => resolve(window.confetti || null);
        script.onerror = () => resolve(null);
        document.head.appendChild(script);
      });
    },
  },
};

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}
