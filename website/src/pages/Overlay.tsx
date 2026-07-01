import { Component } from "react";
import type { CSSProperties, ReactNode } from "react";
import { Link } from "react-router-dom";
import { Thumb } from "../shared/Thumb.tsx";
import type { WindowItem } from "../shared/Thumb.tsx";

type Mode = "everyday" | "app" | "global";
type Held = "cmd" | "opt" | null;

interface OverlayState {
  open: boolean;
  mode: Mode;
  focus: number;
  windows: WindowItem[];
  menuOpen: boolean;
  toast: string | null;
  held: Held;
}

const mono = "'JetBrains Mono',monospace";

export default class Overlay extends Component<Record<string, never>, OverlayState> {
  state: OverlayState = { open: false, mode: "everyday", focus: 1, windows: [], menuOpen: false, toast: null, held: null };
  private _kd?: (e: KeyboardEvent) => void;
  private _ku?: (e: KeyboardEvent) => void;
  private _tt?: ReturnType<typeof setTimeout>;
  private _holdT?: ReturnType<typeof setTimeout>;

  componentDidMount() {
    this._kd = (e) => this.handleDown(e);
    this._ku = (e) => this.handleUp(e);
    window.addEventListener("keydown", this._kd, true);
    window.addEventListener("keyup", this._ku, true);
  }
  componentWillUnmount() {
    if (this._kd) window.removeEventListener("keydown", this._kd, true);
    if (this._ku) window.removeEventListener("keyup", this._ku, true);
    clearTimeout(this._tt);
    clearTimeout(this._holdT);
  }

  // surrogate "modifier" held down — schedule the overlay reveal (hold gesture)
  startHold(which: Held) {
    this.setState({ held: which });
    clearTimeout(this._holdT);
    this._holdT = setTimeout(() => {
      if (this.state.held === which && !this.state.open) this.summon(which === "opt" ? "global" : "everyday");
    }, 220);
  }

  pool(): Record<string, WindowItem> {
    return {
      code: { app: "Code", title: "zentab — BRANDING.md", color: "#3b82f6", letter: "{}", type: "editor" },
      design: { app: "Design", title: "ZenTab — Overlay", color: "#e0563a", letter: "✳", type: "darkui" },
      zen1: { app: "Zen", title: "Zen Browser — Docs", color: "#7c8cff", letter: "z", type: "browser" },
      zen2: { app: "Zen", title: "Issue #214 — GitHub", color: "#7c8cff", letter: "z", type: "browser", badge: "Desktop 2" },
      zen3: { app: "Zen", title: "localhost:3000", color: "#7c8cff", letter: "z", type: "browser", badge: "Minimized" },
      slack: { app: "Slack", title: "#design — Slack", color: "#5bd6a0", letter: "#", type: "chat" },
      term: { app: "Terminal", title: "~/zentab — zsh", color: "#9b9ea9", letter: ">_", type: "terminal" },
      mail: { app: "Mail", title: "Inbox — Mail", color: "#5d6dff", letter: "@", type: "mail", badge: "Display 2" },
      chrome: { app: "Chrome", title: "New Tab — Chrome", color: "#3aa0ff", letter: "○", type: "browser", badge: "Desktop 3" },
    };
  }

  base(mode: Mode): WindowItem[] {
    const p = this.pool();
    if (mode === "app")
      return [
        { ...p.zen1, here: true },
        { ...p.zen2, here: false },
        { ...p.zen3, here: false },
      ];
    if (mode === "global")
      return [
        { ...p.code, here: true },
        { ...p.design, here: true },
        { ...p.zen1, here: true },
        { ...p.slack, here: false, badge: "Desktop 2" },
        { ...p.term, here: false, badge: "Minimized" },
        { ...p.mail, here: false },
        { ...p.chrome, here: false },
      ];
    return [p.code, p.design, p.zen1, p.slack, p.term].map((w) => ({ ...w, here: true }));
  }

  summon(mode: Mode) {
    const wins = this.base(mode);
    this.setState({ open: true, mode, windows: wins, focus: wins.length > 1 ? 1 : 0, menuOpen: false, toast: null });
  }
  tap(mode: Mode) {
    const wins = this.base(mode);
    const target = wins[1] || wins[0];
    this.setState({ menuOpen: false });
    if (!target) {
      this.flash("No other window");
      return;
    }
    this.flash("→ " + target.title);
  }
  toggleMenu() {
    this.setState((s) => ({ menuOpen: !s.menuOpen, open: false }));
  }
  move(d: number) {
    this.setState((s) => {
      const n = s.windows.length;
      if (!n) return null;
      return { focus: (s.focus + d + n) % n };
    });
  }
  setFocus(i: number) {
    this.setState({ focus: i });
  }
  commit() {
    this.setState((s) => {
      const w = s.windows[s.focus];
      return { open: false, toast: w ? "Switched to " + w.title : null, focus: 0 };
    });
    this.scheduleClear();
  }
  cancel() {
    this.setState({ open: false });
  }
  flash(msg: string) {
    this.setState({ toast: msg });
    this.scheduleClear();
  }
  scheduleClear() {
    clearTimeout(this._tt);
    this._tt = setTimeout(() => this.setState({ toast: null }), 1700);
  }
  closeFocused() {
    this.setState((s) => {
      const wins = s.windows.slice();
      wins.splice(s.focus, 1);
      let f = s.focus;
      if (f >= wins.length) f = Math.max(0, wins.length - 1);
      return { windows: wins, focus: f };
    });
  }
  quitFocused() {
    this.setState((s) => {
      const cur = s.windows[s.focus];
      if (!cur) return null;
      const wins = s.windows.filter((w) => w.app !== cur.app);
      let f = s.focus;
      if (f >= wins.length) f = Math.max(0, wins.length - 1);
      return { windows: wins, focus: f };
    });
  }
  handleDown(e: KeyboardEvent) {
    const k = e.key,
      code = e.code;
    if (code === "Space" || k === " ") {
      e.preventDefault();
      if (e.repeat || this.state.held) return;
      this.startHold("cmd");
      return;
    }
    if (k === "v" || k === "V") {
      if (e.repeat || this.state.held) return;
      e.preventDefault();
      this.startHold("opt");
      return;
    }
    if (k === "Tab") {
      if (this.state.held || this.state.open) {
        e.preventDefault();
        clearTimeout(this._holdT);
        if (!this.state.open) this.summon(this.state.held === "opt" ? "global" : "everyday");
        else this.move(e.shiftKey ? -1 : 1);
      }
      return;
    }
    if (k === "`") {
      if (this.state.held === "cmd") {
        e.preventDefault();
        clearTimeout(this._holdT);
        if (!this.state.open || this.state.mode !== "app") this.summon("app");
      }
      return;
    }
    if (!this.state.open) return;
    if (k === "Enter") {
      e.preventDefault();
      this.commit();
      this.setState({ held: null });
    } else if (k === "Escape") {
      e.preventDefault();
      this.cancel();
      this.setState({ held: null });
    } else if (k === "ArrowDown") {
      e.preventDefault();
      this.bringHere();
    } else if (k === "ArrowRight") {
      e.preventDefault();
      this.move(1);
    } else if (k === "ArrowLeft") {
      e.preventDefault();
      this.move(-1);
    } else if (k === "w" || k === "W") {
      e.preventDefault();
      this.closeFocused();
    } else if (k === "q" || k === "Q") {
      e.preventDefault();
      this.quitFocused();
    }
  }
  handleUp(e: KeyboardEvent) {
    const k = e.key,
      code = e.code;
    const isCmd = code === "Space" || k === " ";
    const isOpt = k === "v" || k === "V";
    if (!isCmd && !isOpt) return;
    const which: Held = isCmd ? "cmd" : "opt";
    if (this.state.held !== which) return;
    e.preventDefault();
    clearTimeout(this._holdT);
    if (this.state.open) this.commit();
    else this.tap(which === "opt" ? "global" : "everyday");
    this.setState({ held: null });
  }
  bringHere(i?: number) {
    this.setState((s) => {
      const idx = i == null ? s.focus : i;
      const w = s.windows[idx];
      if (!w || w.here) return null;
      const wins = s.windows.map((x, j) => (j === idx ? { ...x, here: true, badge: null } : x));
      return { windows: wins, toast: "Brought " + w.title + " to this space" };
    });
    this.scheduleClear();
  }

  renderTile(win: WindowItem, i: number): ReactNode {
    const on = i === this.state.focus;
    const here = !!win.here;
    return (
      <div
        key={win.title + i}
        onMouseEnter={() => this.setFocus(i)}
        onClick={() => {
          this.setFocus(i);
          setTimeout(() => this.commit(), 0);
        }}
        style={{
          position: "relative",
          flex: "1 1 180px",
          minWidth: "180px",
          maxWidth: "220px",
          cursor: "pointer",
          borderRadius: "15px",
          padding: "5px",
          border: on ? "2px solid #5d6dff" : "2px solid transparent",
          background: on ? "rgba(93,109,255,0.10)" : "rgba(255,255,255,0.02)",
          boxShadow: on ? "0 12px 34px rgba(93,109,255,0.3)" : "none",
          transition: "all .26s cubic-bezier(.22,.61,.36,1)",
        }}
      >
        <div
          style={{
            position: "absolute",
            top: "11px",
            left: "11px",
            zIndex: 2,
            width: "20px",
            height: "20px",
            borderRadius: "6px",
            background: "rgba(8,9,12,0.7)",
            color: on ? "#fff" : "rgba(255,255,255,0.6)",
            fontSize: "11px",
            fontWeight: 700,
            fontFamily: mono,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          {i + 1}
        </div>
        {on && (
          <div style={{ position: "absolute", top: "9px", right: "9px", zIndex: 2, display: "flex", gap: "5px" }}>
            {!here && (
              <div
                onClick={(e) => {
                  e.stopPropagation();
                  this.bringHere(i);
                }}
                title="Bring to this space"
                style={{ height: "19px", padding: "0 7px", borderRadius: "5px", background: "rgba(93,109,255,0.92)", color: "#fff", fontSize: "9px", fontWeight: 700, fontFamily: mono, display: "flex", alignItems: "center", gap: "3px" }}
              >
                ↓ here
              </div>
            )}
            <div
              onClick={(e) => {
                e.stopPropagation();
                this.closeFocused();
              }}
              title="Close window"
              style={{ width: "19px", height: "19px", borderRadius: "5px", background: "rgba(8,9,12,0.78)", border: "1px solid rgba(255,255,255,0.18)", color: "#fff", fontSize: "9px", fontWeight: 700, fontFamily: mono, display: "flex", alignItems: "center", justifyContent: "center" }}
            >
              W
            </div>
            <div
              onClick={(e) => {
                e.stopPropagation();
                this.quitFocused();
              }}
              title="Quit app"
              style={{ width: "19px", height: "19px", borderRadius: "5px", background: "rgba(8,9,12,0.78)", border: "1px solid rgba(255,255,255,0.18)", color: "#fff", fontSize: "9px", fontWeight: 700, fontFamily: mono, display: "flex", alignItems: "center", justifyContent: "center" }}
            >
              Q
            </div>
          </div>
        )}
        <div style={{ position: "relative", width: "100%", paddingTop: "62%", borderRadius: "10px", overflow: "hidden", border: "1px solid rgba(255,255,255,0.07)" }}>
          <Thumb type={win.type} />
        </div>
        {win.badge && (
          <div style={{ position: "absolute", bottom: "54px", left: "11px", zIndex: 2, fontFamily: mono, fontSize: "9px", letterSpacing: "0.04em", color: "#cfd2dc", background: "rgba(8,9,12,0.7)", borderRadius: "5px", padding: "2px 6px" }}>{win.badge}</div>
        )}
        <div style={{ display: "flex", alignItems: "center", gap: "9px", padding: "10px 6px 5px" }}>
          <div style={{ width: "28px", height: "28px", borderRadius: "7px", flex: "none", background: win.color, display: "flex", alignItems: "center", justifyContent: "center", fontSize: "13px", color: "#fff", fontWeight: 700, fontFamily: mono }}>{win.letter}</div>
          <span style={{ fontSize: "13px", fontWeight: on ? 600 : 500, color: on ? "#ECEDF1" : "#9b9ea9", letterSpacing: "-0.01em", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", transition: "color .26s ease" }}>{win.title}</span>
        </div>
      </div>
    );
  }

  renderTiles(): ReactNode {
    const s = this.state;
    const withIdx = s.windows.map((win, i) => ({ win, i }));
    const elsewhere = withIdx.filter((o) => !o.win.here);
    const hereList = withIdx.filter((o) => o.win.here);
    const row = (arr: { win: WindowItem; i: number }[]) => (
      <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "center", gap: "12px" }}>{arr.map((o) => this.renderTile(o.win, o.i))}</div>
    );
    const zoneHead = (title: string, hint: boolean) => (
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 4px 12px" }}>
        <span style={{ fontFamily: mono, fontSize: "10px", letterSpacing: "0.2em", color: "#62646e", textTransform: "uppercase" }}>{title}</span>
        {hint && <span style={{ fontFamily: mono, fontSize: "11px", color: "#5d6dff", display: "flex", alignItems: "center", gap: "6px" }}>↓ bring here</span>}
      </div>
    );
    if (elsewhere.length === 0) return row(hereList);
    return (
      <div style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
        <div>
          {zoneHead("Elsewhere", true)}
          {row(elsewhere)}
        </div>
        <div style={{ borderTop: "1px solid rgba(255,255,255,0.08)", paddingTop: "18px" }}>
          {zoneHead("This space", false)}
          {hereList.length ? row(hereList) : <div style={{ padding: "10px 6px 4px", fontSize: "13px", color: "#62646e", fontFamily: mono }}>press ↓ to bring a window here</div>}
        </div>
      </div>
    );
  }

  render() {
    const s = this.state;
    const meta = {
      everyday: { key: "⌘ Tab", label: "All windows · this display" },
      app: { key: "⌘ `", label: "Zen Browser · every window, everywhere" },
      global: { key: "⌥ Tab", label: "Everything, everywhere" },
    }[s.mode];
    const countLabel = s.windows.length + (s.windows.length === 1 ? " window" : " windows");
    const hasWindows = s.open && s.windows.length > 0;
    const isEmpty = s.open && s.windows.length === 0;

    const kbd: CSSProperties = { display: "inline-flex", alignItems: "center", fontFamily: mono, fontSize: "12px", background: "var(--cardhi)", border: "1px solid var(--bdhi)", borderBottomWidth: "2px", borderRadius: "6px", padding: "4px 9px", color: "var(--tx)" };
    const tapBtn: CSSProperties = { flex: 1, fontFamily: mono, fontSize: "12px", color: "var(--dim)", background: "rgba(255,255,255,0.03)", border: "1px solid var(--bd)", borderRadius: "10px", padding: "10px", cursor: "pointer" };
    const holdBtn: CSSProperties = { flex: 1, fontFamily: mono, fontSize: "12px", color: "#fff", background: "rgba(93,109,255,0.18)", border: "1px solid rgba(93,109,255,0.45)", borderRadius: "10px", padding: "10px", cursor: "pointer" };
    const hint: CSSProperties = { fontFamily: mono, fontSize: "11px", color: "var(--faint)" };

    const root: CSSProperties = {
      ["--bg" as string]: "#0b0c0f",
      ["--card" as string]: "rgba(255,255,255,0.025)",
      ["--cardhi" as string]: "rgba(255,255,255,0.05)",
      ["--bd" as string]: "rgba(255,255,255,0.075)",
      ["--bdhi" as string]: "rgba(255,255,255,0.14)",
      ["--tx" as string]: "#ECEDF1",
      ["--dim" as string]: "#9b9ea9",
      ["--faint" as string]: "#5e616c",
      ["--accent" as string]: "#5d6dff",
      fontFamily: "'Schibsted Grotesk',sans-serif",
      color: "var(--tx)",
      background: "radial-gradient(140% 90% at 80% -10%, #14161f 0%, #0b0c0f 55%)",
      minHeight: "100vh",
      padding: "36px 40px 70px",
    };

    return (
      <div style={root}>
        <div style={{ maxWidth: "1240px", margin: "0 auto" }}>
          {/* header */}
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "8px", animation: "ovUp .6s ease" }}>
            <Link to="/" style={{ display: "flex", alignItems: "center", gap: "11px" }}>
              <div style={{ position: "relative", width: "26px", height: "26px", flex: "none" }}>
                <div style={{ position: "absolute", inset: 0, border: "1.5px solid var(--bdhi)", borderRadius: "7px" }} />
                <div style={{ position: "absolute", left: "8px", top: "8px", width: "18px", height: "18px", background: "var(--accent)", borderRadius: "6px", boxShadow: "0 4px 14px rgba(93,109,255,0.5)" }} />
              </div>
              <span style={{ fontWeight: 600, letterSpacing: "-0.02em", fontSize: "17px" }}>ZenTab</span>
            </Link>
            <span style={{ fontFamily: mono, fontSize: "11px", letterSpacing: "0.18em", color: "var(--faint)", textTransform: "uppercase" }}>Product — the overlay</span>
          </div>
          <h1 style={{ fontSize: "40px", fontWeight: 700, letterSpacing: "-0.04em", marginBottom: "8px", animation: "ovUp .6s .05s ease" }}>Summon it. Switch. It's gone.</h1>
          <p style={{ fontSize: "17px", color: "var(--dim)", maxWidth: "660px", lineHeight: 1.5, marginBottom: "22px", animation: "ovUp .6s .1s ease" }}>
            A live, playable overlay — driven by your keyboard. ⌘Tab and ⌥Tab belong to your OS, so this demo maps the same gestures to safe stand-ins. Click the desktop, then try:
          </p>

          <div style={{ background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "18px", padding: "20px 24px", marginBottom: "22px", animation: "ovUp .6s .14s ease" }}>
            <div style={{ display: "flex", flexWrap: "wrap", gap: "14px 30px", alignItems: "center" }}>
              <div style={{ display: "flex", alignItems: "center", gap: "9px" }}>
                <kbd style={kbd}>hold Space</kbd>
                <span style={{ color: "var(--faint)", fontSize: "13px" }}>+</span>
                <kbd style={kbd}>Tab</kbd>
                <span style={{ fontSize: "14px", color: "var(--dim)", marginLeft: "4px" }}>Everyday</span>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: "9px" }}>
                <kbd style={kbd}>hold Space</kbd>
                <span style={{ color: "var(--faint)", fontSize: "13px" }}>then</span>
                <kbd style={kbd}>`</kbd>
                <span style={{ fontSize: "14px", color: "var(--dim)", marginLeft: "4px" }}>Current app</span>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: "9px" }}>
                <kbd style={kbd}>hold V</kbd>
                <span style={{ color: "var(--faint)", fontSize: "13px" }}>+</span>
                <kbd style={kbd}>Tab</kbd>
                <span style={{ fontSize: "14px", color: "var(--dim)", marginLeft: "4px" }}>Global</span>
              </div>
            </div>
            <div style={{ marginTop: "16px", borderTop: "1px solid var(--bd)", paddingTop: "15px", display: "flex", flexWrap: "wrap", gap: "9px 20px", fontFamily: mono, fontSize: "11.5px", color: "var(--faint)" }}>
              <span><span style={{ color: "var(--dim)" }}>tap</span> instant switch</span>
              <span><span style={{ color: "var(--dim)" }}>hold</span> show overlay</span>
              <span><span style={{ color: "var(--dim)" }}>release</span> commit</span>
              <span><span style={{ color: "var(--accent)" }}>↓</span> bring window to this space</span>
              <span><span style={{ color: "var(--dim)" }}>W</span> close</span>
              <span><span style={{ color: "var(--dim)" }}>Q</span> quit</span>
              <span><span style={{ color: "var(--dim)" }}>Esc</span> cancel</span>
            </div>
          </div>

          {/* THE SCREEN */}
          <div style={{ position: "relative", width: "100%", aspectRatio: "16/10", borderRadius: "16px", overflow: "hidden", border: "1px solid #20222b", boxShadow: "0 40px 120px rgba(0,0,0,0.6), inset 0 0 0 1px rgba(255,255,255,0.03)", background: "radial-gradient(120% 120% at 30% 10%, #1f3550 0%, #14202f 38%, #0c1119 75%)", animation: "ovUp .7s .15s ease" }}>
            {/* wallpaper atmosphere */}
            <div style={{ position: "absolute", top: "-15%", left: "-10%", width: "55%", height: "70%", borderRadius: "50%", background: "radial-gradient(circle,rgba(93,109,255,0.18),transparent 65%)", filter: "blur(10px)" }} />
            <div style={{ position: "absolute", bottom: "-20%", right: "-5%", width: "45%", height: "60%", borderRadius: "50%", background: "radial-gradient(circle,rgba(91,214,160,0.10),transparent 65%)", filter: "blur(10px)" }} />

            {/* faux desktop windows (context) */}
            <div style={{ position: "absolute", left: "6%", top: "18%", width: "40%", height: "54%", borderRadius: "11px", background: "rgba(18,20,26,0.82)", border: "1px solid rgba(255,255,255,0.06)", boxShadow: "0 20px 50px rgba(0,0,0,0.4)", overflow: "hidden" }}>
              <div style={{ height: "26px", background: "rgba(255,255,255,0.04)", display: "flex", alignItems: "center", gap: "6px", padding: "0 11px" }}>
                <div style={{ width: "9px", height: "9px", borderRadius: "50%", background: "#ff5f57" }} />
                <div style={{ width: "9px", height: "9px", borderRadius: "50%", background: "#febc2e" }} />
                <div style={{ width: "9px", height: "9px", borderRadius: "50%", background: "#28c840" }} />
              </div>
              <div style={{ padding: "16px", display: "flex", flexDirection: "column", gap: "9px" }}>
                <div style={{ width: "55%", height: "7px", borderRadius: "3px", background: "rgba(93,109,255,0.55)" }} />
                <div style={{ width: "85%", height: "6px", borderRadius: "3px", background: "rgba(255,255,255,0.14)" }} />
                <div style={{ width: "72%", height: "6px", borderRadius: "3px", background: "rgba(255,255,255,0.14)" }} />
                <div style={{ width: "90%", height: "6px", borderRadius: "3px", background: "rgba(255,255,255,0.14)" }} />
                <div style={{ width: "48%", height: "6px", borderRadius: "3px", background: "rgba(91,214,160,0.4)" }} />
              </div>
            </div>
            <div style={{ position: "absolute", right: "8%", top: "30%", width: "38%", height: "50%", borderRadius: "11px", background: "rgba(244,242,236,0.95)", border: "1px solid rgba(0,0,0,0.1)", boxShadow: "0 20px 50px rgba(0,0,0,0.35)", overflow: "hidden" }}>
              <div style={{ height: "26px", background: "#e7e3d8", display: "flex", alignItems: "center", gap: "6px", padding: "0 11px" }}>
                <div style={{ width: "9px", height: "9px", borderRadius: "50%", background: "#c8c2b2" }} />
                <div style={{ width: "9px", height: "9px", borderRadius: "50%", background: "#c8c2b2" }} />
              </div>
              <div style={{ padding: "18px", display: "flex", flexDirection: "column", gap: "9px" }}>
                <div style={{ width: "60%", height: "9px", borderRadius: "3px", background: "#33312b" }} />
                <div style={{ width: "90%", height: "6px", borderRadius: "3px", background: "rgba(0,0,0,0.16)" }} />
                <div style={{ width: "80%", height: "6px", borderRadius: "3px", background: "rgba(0,0,0,0.16)" }} />
              </div>
            </div>

            {/* MENU BAR */}
            <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: "30px", background: "rgba(12,14,19,0.55)", backdropFilter: "blur(20px)", WebkitBackdropFilter: "blur(20px)", borderBottom: "1px solid rgba(255,255,255,0.06)", display: "flex", alignItems: "center", padding: "0 14px", zIndex: 20 }}>
              <div style={{ display: "flex", alignItems: "center", gap: "18px", fontSize: "12.5px", color: "rgba(255,255,255,0.85)" }}>
                <div style={{ width: "13px", height: "13px", borderRadius: "3px", background: "rgba(255,255,255,0.85)" }} />
                <span style={{ fontWeight: 700 }}>Zen</span>
                <span style={{ opacity: 0.75 }}>File</span>
                <span style={{ opacity: 0.75 }}>Edit</span>
                <span style={{ opacity: 0.75 }}>View</span>
              </div>
              <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: "15px", fontFamily: mono, fontSize: "11.5px", color: "rgba(255,255,255,0.8)" }}>
                <div onClick={() => this.toggleMenu()} style={{ position: "relative", width: "17px", height: "17px", cursor: "pointer" }} title="ZenTab">
                  <div style={{ position: "absolute", inset: 0, border: "1.4px solid rgba(255,255,255,0.65)", borderRadius: "5px" }} />
                  <div style={{ position: "absolute", left: "5px", top: "5px", width: "12px", height: "12px", background: "var(--accent)", borderRadius: "4px" }} />
                </div>
                <span>100%</span>
                <span style={{ letterSpacing: "0.02em" }}>9:41</span>
              </div>
            </div>

            {/* TRAY MENU */}
            {s.menuOpen && (
              <div style={{ position: "absolute", top: "34px", right: "14px", width: "268px", background: "rgba(22,24,31,0.82)", backdropFilter: "blur(26px)", WebkitBackdropFilter: "blur(26px)", border: "1px solid rgba(255,255,255,0.12)", borderRadius: "14px", boxShadow: "0 24px 60px rgba(0,0,0,0.55)", zIndex: 30, overflow: "hidden", animation: "ovIn .14s ease", fontSize: "13px" }}>
                <div style={{ padding: "14px 15px", display: "flex", alignItems: "center", gap: "10px", borderBottom: "1px solid rgba(255,255,255,0.06)" }}>
                  <div style={{ width: "7px", height: "7px", borderRadius: "50%", background: "#5bd6a0", boxShadow: "0 0 8px #5bd6a0" }} />
                  <span style={{ fontWeight: 600 }}>ZenTab is running</span>
                  <span style={{ marginLeft: "auto", fontFamily: mono, fontSize: "10px", color: "var(--faint)" }}>idle · 0% cpu</span>
                </div>
                <div style={{ padding: "7px 0" }}>
                  <div className="zt-menu-item" onClick={() => this.summon("everyday")} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "8px 15px", cursor: "pointer" }}>
                    <span>Everyday switch</span>
                    <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>⌘ Tab</span>
                  </div>
                  <div className="zt-menu-item" onClick={() => this.summon("app")} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "8px 15px", cursor: "pointer" }}>
                    <span>Current-app windows</span>
                    <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>⌘ `</span>
                  </div>
                  <div className="zt-menu-item" onClick={() => this.summon("global")} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "8px 15px", cursor: "pointer" }}>
                    <span>Global escape hatch</span>
                    <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>⌥ Tab</span>
                  </div>
                </div>
                <div style={{ borderTop: "1px solid rgba(255,255,255,0.06)", padding: "7px 0" }}>
                  <div style={{ padding: "8px 15px", color: "var(--faint)", fontSize: "11.5px" }}>Free forever · no account</div>
                  <div className="zt-menu-item" style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "8px 15px", cursor: "pointer", color: "var(--dim)" }}>
                    <span>Quit ZenTab</span>
                    <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>⌘ Q</span>
                  </div>
                </div>
              </div>
            )}

            {/* OVERLAY */}
            {s.open && (
              <div onClick={() => this.cancel()} style={{ position: "absolute", inset: 0, background: "rgba(6,7,10,0.55)", backdropFilter: "blur(6px)", WebkitBackdropFilter: "blur(6px)", zIndex: 40, display: "flex", alignItems: "center", justifyContent: "center", animation: "ovBack .12s ease" }}>
                <div onClick={(e) => e.stopPropagation()} style={{ width: "min(92%,1060px)", background: "rgba(24,26,33,0.7)", backdropFilter: "blur(30px)", WebkitBackdropFilter: "blur(30px)", border: "1px solid rgba(255,255,255,0.12)", borderRadius: "24px", boxShadow: "0 40px 120px rgba(0,0,0,0.6)", padding: "22px", animation: "ovIn .14s cubic-bezier(.22,.61,.36,1)" }}>
                  <div style={{ display: "flex", alignItems: "center", gap: "12px", padding: "2px 6px 18px" }}>
                    <span style={{ fontFamily: mono, fontSize: "12px", letterSpacing: "0.04em", color: "var(--accent)", border: "1px solid rgba(93,109,255,0.35)", borderRadius: "7px", padding: "5px 9px" }}>{meta.key}</span>
                    <span style={{ fontSize: "15px", fontWeight: 600, letterSpacing: "-0.01em" }}>{meta.label}</span>
                    <span style={{ marginLeft: "auto", fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>{countLabel}</span>
                  </div>
                  {hasWindows && this.renderTiles()}
                  {isEmpty && (
                    <div style={{ padding: "54px 20px", textAlign: "center" }}>
                      <div style={{ width: "46px", height: "46px", margin: "0 auto 16px", border: "1.6px dashed rgba(255,255,255,0.2)", borderRadius: "13px" }} />
                      <div style={{ fontSize: "17px", fontWeight: 600, marginBottom: "6px" }}>Nothing left here</div>
                      <div style={{ fontSize: "14px", color: "var(--dim)" }}>No windows in this scope. Esc to dismiss — ZenTab steps back.</div>
                    </div>
                  )}
                  <div style={{ display: "flex", alignItems: "center", gap: "16px", padding: "16px 6px 2px", marginTop: "6px", borderTop: "1px solid rgba(255,255,255,0.07)", flexWrap: "wrap" }}>
                    <span style={hint}><span style={{ color: "var(--dim)" }}>Tab</span> move</span>
                    <span style={hint}><span style={{ color: "var(--dim)" }}>↵</span> switch</span>
                    <span style={hint}><span style={{ color: "var(--dim)" }}>W</span> close window</span>
                    <span style={hint}><span style={{ color: "var(--dim)" }}>Q</span> quit app</span>
                    <span style={hint}><span style={{ color: "var(--accent)" }}>↓</span> bring here</span>
                    <span style={{ ...hint, marginLeft: "auto" }}><span style={{ color: "var(--dim)" }}>Esc</span> cancel</span>
                  </div>
                </div>
              </div>
            )}

            {/* TOAST */}
            {s.toast && (
              <div style={{ position: "absolute", bottom: "26px", left: "50%", transform: "translateX(-50%)", zIndex: 50, background: "rgba(24,26,33,0.85)", backdropFilter: "blur(20px)", WebkitBackdropFilter: "blur(20px)", border: "1px solid rgba(255,255,255,0.12)", borderRadius: "12px", padding: "11px 18px", display: "flex", alignItems: "center", gap: "11px", boxShadow: "0 18px 50px rgba(0,0,0,0.5)", animation: "ovToast .18s ease" }}>
                <div style={{ width: "7px", height: "7px", borderRadius: "2px", background: "var(--accent)", boxShadow: "0 0 10px rgba(93,109,255,0.8)" }} />
                <span style={{ fontSize: "14px", fontWeight: 500, letterSpacing: "-0.01em" }}>{s.toast}</span>
              </div>
            )}
          </div>

          {/* CONTROLS */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: "14px", marginTop: "18px" }}>
            {[
              { n: "01", title: "Everyday", key: "⌘ Tab", body: "Every window on this display + desktop.", tap: () => this.tap("everyday"), hold: () => this.summon("everyday") },
              { n: "02", title: "Current app", key: "⌘ `", body: "Every window of the active app, from anywhere.", tap: () => this.tap("app"), hold: () => this.summon("app") },
              { n: "03", title: "Global", key: "⌥ Tab", body: 'Everything, everywhere. The "I lost something" valve.', tap: () => this.tap("global"), hold: () => this.summon("global") },
            ].map((c) => (
              <div key={c.n} style={{ background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "18px", padding: "20px" }}>
                <div style={{ display: "flex", alignItems: "center", gap: "9px", marginBottom: "6px" }}>
                  <span style={{ fontFamily: mono, fontSize: "12px", color: "var(--accent)" }}>{c.n}</span>
                  <span style={{ fontSize: "16px", fontWeight: 600, letterSpacing: "-0.01em" }}>{c.title}</span>
                  <span style={{ marginLeft: "auto", fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>{c.key}</span>
                </div>
                <div style={{ fontSize: "13px", color: "var(--dim)", lineHeight: 1.45, marginBottom: "16px" }}>{c.body}</div>
                <div style={{ display: "flex", gap: "8px" }}>
                  <button onClick={c.tap} style={tapBtn}>Tap</button>
                  <button onClick={c.hold} style={holdBtn}>Hold</button>
                </div>
              </div>
            ))}
          </div>

          {/* tap vs hold + pillars */}
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "14px", marginTop: "14px" }}>
            <div style={{ background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "18px", padding: "24px" }}>
              <div style={{ fontFamily: mono, fontSize: "11px", letterSpacing: "0.14em", color: "var(--faint)", textTransform: "uppercase", marginBottom: "14px" }}>The one gesture, two outcomes</div>
              <div style={{ display: "flex", gap: "24px" }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: "18px", fontWeight: 600, letterSpacing: "-0.01em", marginBottom: "6px" }}>Tap</div>
                  <div style={{ fontSize: "14px", color: "var(--dim)", lineHeight: 1.5 }}>Instant switch to the most-recent other window. No overlay ever appears.</div>
                </div>
                <div style={{ width: "1px", background: "var(--bd)" }} />
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: "18px", fontWeight: 600, letterSpacing: "-0.01em", marginBottom: "6px" }}>Hold</div>
                  <div style={{ fontSize: "14px", color: "var(--dim)", lineHeight: 1.5 }}>The overlay appears with a stable list. Release commits; click outside cancels.</div>
                </div>
              </div>
            </div>
            <div style={{ background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "18px", padding: "24px" }}>
              <div style={{ fontFamily: mono, fontSize: "11px", letterSpacing: "0.14em", color: "var(--faint)", textTransform: "uppercase", marginBottom: "14px" }}>Non-negotiable</div>
              <div style={{ display: "flex", flexDirection: "column", gap: "11px" }}>
                {[
                  { lead: "Stable order.", rest: " Tiles never reshuffle by recency — Slack is always 4th." },
                  { lead: "Two actions only.", rest: " W closes, Q quits. Window management is the OS's job." },
                  { lead: "No settings.", rest: " The behavior is settled, on purpose. Nothing to tune." },
                ].map((p) => (
                  <div key={p.lead} style={{ display: "flex", gap: "11px", alignItems: "flex-start" }}>
                    <div style={{ width: "6px", height: "6px", borderRadius: "50%", background: "var(--accent)", marginTop: "7px", flex: "none" }} />
                    <span style={{ fontSize: "14px", color: "var(--dim)", lineHeight: 1.45 }}>
                      <span style={{ color: "var(--tx)" }}>{p.lead}</span>
                      {p.rest}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }
}
