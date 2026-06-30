import { Component } from "react";
import type { CSSProperties, ReactNode } from "react";
import { Link } from "react-router-dom";
import { Thumb } from "../shared/Thumb.tsx";
import type { WindowItem } from "../shared/Thumb.tsx";

type Mode = "everyday" | "app" | "global";

interface LandingState {
  mode: Mode;
  focus: number;
  auto: boolean;
  toast: string | null;
}

const mono = "'JetBrains Mono',monospace";

export default class Landing extends Component<Record<string, never>, LandingState> {
  state: LandingState = { mode: "everyday", focus: 1, auto: true, toast: null };
  private _iv?: ReturnType<typeof setInterval>;
  private _tt?: ReturnType<typeof setTimeout>;

  componentDidMount() {
    this._iv = setInterval(() => {
      if (!this.state.auto) return;
      this.setState((s) => {
        const n = this.base(s.mode).length;
        return { focus: (s.focus + 1) % n };
      });
    }, 2000);
  }
  componentWillUnmount() {
    clearInterval(this._iv);
    clearTimeout(this._tt);
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
    };
  }
  base(mode: Mode): WindowItem[] {
    const p = this.pool();
    if (mode === "app") return [p.zen1, p.zen2, p.zen3];
    if (mode === "global") return [p.code, p.design, p.zen1, p.slack, p.term];
    return [p.code, p.design, p.zen1, p.slack];
  }

  setMode(m: Mode) {
    this.setState({ mode: m, focus: 1, toast: null });
  }
  pick(i: number) {
    const w = this.base(this.state.mode)[i];
    this.setState({ focus: i, toast: w ? "Switched to " + w.title : null });
    clearTimeout(this._tt);
    this._tt = setTimeout(() => this.setState({ toast: null }), 1700);
  }

  renderTile(win: WindowItem, i: number): ReactNode {
    const on = i === this.state.focus;
    return (
      <div
        key={win.title + i}
        onMouseEnter={() => this.setState({ focus: i })}
        onClick={() => this.pick(i)}
        style={{
          position: "relative",
          flex: "1 1 150px",
          minWidth: "140px",
          maxWidth: "200px",
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
            width: "18px",
            height: "18px",
            borderRadius: "5px",
            background: "rgba(8,9,12,0.7)",
            color: on ? "#fff" : "rgba(255,255,255,0.55)",
            fontSize: "10px",
            fontWeight: 700,
            fontFamily: mono,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          {i + 1}
        </div>
        {win.badge && (
          <div
            style={{
              position: "absolute",
              bottom: "44px",
              left: "11px",
              zIndex: 2,
              fontFamily: mono,
              fontSize: "9px",
              letterSpacing: "0.04em",
              color: "#cfd2dc",
              background: "rgba(8,9,12,0.7)",
              borderRadius: "5px",
              padding: "2px 6px",
            }}
          >
            {win.badge}
          </div>
        )}
        <div
          style={{
            position: "relative",
            width: "100%",
            paddingTop: "60%",
            borderRadius: "10px",
            overflow: "hidden",
            border: "1px solid rgba(255,255,255,0.07)",
          }}
        >
          <Thumb type={win.type} />
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "8px", padding: "9px 5px 4px" }}>
          <div
            style={{
              width: "18px",
              height: "18px",
              borderRadius: "5px",
              flex: "none",
              background: win.color,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: "9px",
              color: "#fff",
              fontWeight: 700,
              fontFamily: mono,
            }}
          >
            {win.letter}
          </div>
          <span
            style={{
              fontSize: "12.5px",
              fontWeight: on ? 600 : 500,
              color: on ? "#ECEDF1" : "#9b9ea9",
              letterSpacing: "-0.01em",
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
              transition: "color .26s ease",
            }}
          >
            {win.title}
          </span>
        </div>
      </div>
    );
  }

  render() {
    const s = this.state;
    const wins = this.base(s.mode);
    const meta = {
      everyday: { key: "⌘ Tab", label: "All windows · this display" },
      app: { key: "⌘ `", label: "Zen Browser · every window, everywhere" },
      global: { key: "⌥ Tab", label: "Everything, everywhere" },
    }[s.mode];

    const chip = (m: Mode) => {
      const active = s.mode === m;
      return {
        bg: active ? "rgba(93,109,255,0.16)" : "rgba(255,255,255,0.025)",
        bd: active ? "rgba(93,109,255,0.5)" : "rgba(255,255,255,0.075)",
        fg: active ? "#ECEDF1" : "#9b9ea9",
      };
    };
    const c0 = chip("everyday");
    const c1 = chip("app");
    const c2 = chip("global");
    const chipStyle = (c: { bg: string; bd: string; fg: string }): CSSProperties => ({
      display: "flex",
      alignItems: "center",
      gap: "9px",
      fontSize: "13px",
      background: c.bg,
      border: `1px solid ${c.bd}`,
      color: c.fg,
      borderRadius: "10px",
      padding: "9px 14px",
      cursor: "pointer",
      transition: "all .2s",
    });

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
      background: "radial-gradient(130% 80% at 78% -8%, #14161f 0%, #0b0c0f 52%)",
      overflowX: "hidden",
      position: "relative",
    };

    return (
      <div style={root}>
        {/* NAV */}
        <nav
          style={{
            position: "sticky",
            top: 0,
            zIndex: 60,
            backdropFilter: "blur(18px)",
            WebkitBackdropFilter: "blur(18px)",
            background: "rgba(11,12,15,0.6)",
            borderBottom: "1px solid var(--bd)",
          }}
        >
          <div style={{ maxWidth: "1200px", margin: "0 auto", padding: "15px 32px", display: "flex", alignItems: "center", gap: "30px" }}>
            <a href="#top" style={{ display: "flex", alignItems: "center", gap: "10px" }}>
              <div style={{ position: "relative", width: "24px", height: "24px", flex: "none" }}>
                <div style={{ position: "absolute", inset: 0, border: "1.5px solid var(--bdhi)", borderRadius: "7px" }} />
                <div style={{ position: "absolute", left: "7px", top: "7px", width: "17px", height: "17px", background: "var(--accent)", borderRadius: "6px", boxShadow: "0 4px 12px rgba(93,109,255,0.5)" }} />
              </div>
              <span style={{ fontWeight: 600, letterSpacing: "-0.02em", fontSize: "16px" }}>ZenTab</span>
            </a>
            <div style={{ display: "flex", gap: "26px", marginLeft: "14px", fontSize: "14px", color: "var(--dim)" }}>
              <a href="#feel" className="zt-link">The feel</a>
              <a href="#modes" className="zt-link">Three modes</a>
              <a href="#config" className="zt-link">Config</a>
              <Link to="/overlay" className="zt-link">Live overlay</Link>
              <a href="#free" className="zt-link">Pricing</a>
            </div>
            <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: "14px" }}>
              <Link to="/brand" className="zt-link" style={{ fontSize: "13.5px", color: "var(--dim)" }}>Brand</Link>
              <a href="#download" className="zt-btn-primary" style={{ fontSize: "13.5px", fontWeight: 600, background: "var(--tx)", color: "#0b0c0f", borderRadius: "9px", padding: "9px 16px" }}>Download</a>
            </div>
          </div>
        </nav>

        {/* HERO */}
        <section id="top" style={{ position: "relative", maxWidth: "1200px", margin: "0 auto", padding: "88px 32px 60px" }}>
          <div style={{ position: "absolute", top: "-80px", right: "-60px", width: "560px", height: "560px", borderRadius: "50%", background: "radial-gradient(circle,rgba(93,109,255,0.16) 0%,transparent 62%)", filter: "blur(20px)", pointerEvents: "none", animation: "ztDrift 18s ease-in-out infinite" }} />
          <div style={{ position: "relative", zIndex: 2, textAlign: "center", maxWidth: "860px", margin: "0 auto" }}>
            <div style={{ display: "inline-flex", alignItems: "center", gap: "9px", border: "1px solid var(--bd)", borderRadius: "999px", padding: "7px 14px", marginBottom: "30px", animation: "ztUp .7s ease" }}>
              <span style={{ width: "6px", height: "6px", borderRadius: "50%", background: "#5bd6a0", boxShadow: "0 0 8px #5bd6a0", animation: "ztPulse 2.4s ease-in-out infinite" }} />
              <span style={{ fontFamily: mono, fontSize: "11.5px", letterSpacing: "0.06em", color: "var(--dim)" }}>macOS &amp; Windows · v1.0</span>
            </div>
            <h1 style={{ fontSize: "clamp(44px,7vw,88px)", fontWeight: 700, letterSpacing: "-0.045em", lineHeight: 0.98, marginBottom: "24px", animation: "ztUp .8s .05s ease" }}>
              Window switching
              <br />
              that feels instant.
            </h1>
            <p style={{ fontSize: "clamp(17px,2.2vw,21px)", color: "var(--dim)", lineHeight: 1.5, maxWidth: "620px", margin: "0 auto 36px", animation: "ztUp .8s .12s ease" }}>
              A calm, instant window switcher for macOS and Windows. Tap to land in the window you want — or hold, and every window steps gently into view while the rest of the world recedes.
            </p>
            <div style={{ display: "flex", gap: "12px", justifyContent: "center", alignItems: "center", flexWrap: "wrap", animation: "ztUp .8s .18s ease" }}>
              <a href="#download" className="zt-cta" style={{ display: "inline-flex", alignItems: "center", gap: "9px", fontSize: "15px", fontWeight: 600, background: "var(--tx)", color: "#0b0c0f", borderRadius: "12px", padding: "14px 22px", transition: "transform .2s" }}>Download for macOS</a>
              <Link to="/overlay" className="zt-soft" style={{ fontSize: "15px", fontWeight: 500, color: "var(--dim)", border: "1px solid var(--bd)", borderRadius: "12px", padding: "14px 20px", transition: "all .2s" }}>Try the live overlay</Link>
            </div>
            <div style={{ fontFamily: mono, fontSize: "11.5px", color: "var(--faint)", marginTop: "18px", animation: "ztUp .8s .24s ease" }}>Free forever · 4.2 MB · macOS &amp; Windows</div>
          </div>

          {/* LIVE HERO DEMO */}
          <div
            onMouseEnter={() => this.setState({ auto: false })}
            onMouseLeave={() => this.setState({ auto: true })}
            style={{ position: "relative", zIndex: 2, marginTop: "64px", borderRadius: "18px", overflow: "hidden", border: "1px solid #20222b", boxShadow: "0 50px 140px rgba(0,0,0,0.65)", background: "radial-gradient(120% 120% at 30% 8%, #1f3550 0%, #14202f 40%, #0c1119 78%)", aspectRatio: "16/9", animation: "ztUp 1s .3s ease" }}
          >
            <div style={{ position: "absolute", top: "-12%", left: "-8%", width: "50%", height: "65%", borderRadius: "50%", background: "radial-gradient(circle,rgba(93,109,255,0.16),transparent 65%)", filter: "blur(10px)" }} />
            <div style={{ position: "absolute", bottom: "-18%", right: "-4%", width: "42%", height: "58%", borderRadius: "50%", background: "radial-gradient(circle,rgba(91,214,160,0.09),transparent 65%)", filter: "blur(10px)" }} />

            {/* menubar */}
            <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: "28px", background: "rgba(12,14,19,0.5)", backdropFilter: "blur(16px)", WebkitBackdropFilter: "blur(16px)", borderBottom: "1px solid rgba(255,255,255,0.06)", display: "flex", alignItems: "center", padding: "0 14px", zIndex: 5 }}>
              <div style={{ width: "12px", height: "12px", borderRadius: "3px", background: "rgba(255,255,255,0.8)" }} />
              <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: "13px", fontFamily: mono, fontSize: "11px", color: "rgba(255,255,255,0.78)" }}>
                <div style={{ position: "relative", width: "15px", height: "15px" }}>
                  <div style={{ position: "absolute", inset: 0, border: "1.3px solid rgba(255,255,255,0.6)", borderRadius: "5px" }} />
                  <div style={{ position: "absolute", left: "5px", top: "5px", width: "10px", height: "10px", background: "var(--accent)", borderRadius: "3px" }} />
                </div>
                <span>9:41</span>
              </div>
            </div>

            {/* overlay panel */}
            <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", padding: "0 28px" }}>
              <div style={{ width: "min(94%,920px)", background: "rgba(24,26,33,0.66)", backdropFilter: "blur(28px)", WebkitBackdropFilter: "blur(28px)", border: "1px solid rgba(255,255,255,0.12)", borderRadius: "22px", boxShadow: "0 40px 110px rgba(0,0,0,0.55)", padding: "20px" }}>
                <div style={{ display: "flex", alignItems: "center", gap: "11px", padding: "2px 6px 16px" }}>
                  <span style={{ fontFamily: mono, fontSize: "11.5px", letterSpacing: "0.04em", color: "var(--accent)", border: "1px solid rgba(93,109,255,0.35)", borderRadius: "7px", padding: "5px 9px" }}>{meta.key}</span>
                  <span style={{ fontSize: "14px", fontWeight: 600, letterSpacing: "-0.01em" }}>{meta.label}</span>
                  <span style={{ marginLeft: "auto", fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>hold to reveal</span>
                </div>
                <div style={{ display: "flex", flexWrap: "wrap", gap: "12px" }}>{wins.map((win, i) => this.renderTile(win, i))}</div>
              </div>
            </div>

            {/* toast */}
            {s.toast && (
              <div style={{ position: "absolute", bottom: "22px", left: "50%", transform: "translateX(-50%)", zIndex: 8, background: "rgba(24,26,33,0.85)", backdropFilter: "blur(18px)", WebkitBackdropFilter: "blur(18px)", border: "1px solid rgba(255,255,255,0.12)", borderRadius: "12px", padding: "10px 17px", display: "flex", alignItems: "center", gap: "10px", boxShadow: "0 16px 44px rgba(0,0,0,0.5)" }}>
                <div style={{ width: "7px", height: "7px", borderRadius: "2px", background: "var(--accent)", boxShadow: "0 0 9px rgba(93,109,255,0.8)" }} />
                <span style={{ fontSize: "13.5px", fontWeight: 500, letterSpacing: "-0.01em" }}>{s.toast}</span>
              </div>
            )}
          </div>

          {/* mode chips under demo */}
          <div style={{ position: "relative", zIndex: 2, display: "flex", gap: "10px", justifyContent: "center", marginTop: "18px", flexWrap: "wrap", animation: "ztUp 1s .4s ease" }}>
            <button onClick={() => this.setMode("everyday")} style={chipStyle(c0)}>
              Everyday <span style={{ fontFamily: mono, fontSize: "11px", opacity: 0.7 }}>⌘ Tab</span>
            </button>
            <button onClick={() => this.setMode("app")} style={chipStyle(c1)}>
              Current app <span style={{ fontFamily: mono, fontSize: "11px", opacity: 0.7 }}>⌘ `</span>
            </button>
            <button onClick={() => this.setMode("global")} style={chipStyle(c2)}>
              Global <span style={{ fontFamily: mono, fontSize: "11px", opacity: 0.7 }}>⌥ Tab</span>
            </button>
            <span style={{ display: "flex", alignItems: "center", fontFamily: mono, fontSize: "11px", color: "var(--faint)", marginLeft: "6px" }}>hover the tiles to take over</span>
          </div>
        </section>

        {/* PILLARS */}
        <section style={{ position: "relative", maxWidth: "1200px", margin: "0 auto", padding: "60px 32px 10px" }}>
          <div style={{ fontFamily: mono, fontSize: "12px", letterSpacing: "0.22em", color: "var(--faint)", textTransform: "uppercase", marginBottom: "22px" }}>Built on five opinions</div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(5,1fr)", gap: "1px", background: "var(--bd)", border: "1px solid var(--bd)", borderRadius: "18px", overflow: "hidden" }}>
            {[
              { icon: <div style={{ width: "20px", height: "20px", background: "linear-gradient(145deg,#7282ff,#5160ff)", borderRadius: "6px" }} />, title: "Very opinionated", body: "One considered path, chosen for you." },
              { icon: <div style={{ width: "20px", height: "20px", border: "1.6px solid var(--bdhi)", borderRadius: "6px" }} />, title: "No settings", body: "No knobs to turn. Nothing to distract." },
              { icon: <div style={{ width: "20px", height: "20px", display: "flex", alignItems: "center", justifyContent: "center", fontFamily: mono, fontSize: "17px", color: "var(--accent)" }}>∞</div>, title: "Free forever", body: "For everyone. Always. Truly." },
              { icon: <div style={{ width: "20px", height: "20px", display: "flex", alignItems: "center" }}><div style={{ width: "20px", height: "3px", background: "var(--accent)", borderRadius: "2px" }} /></div>, title: "Featherlight", body: "~4 MB, and invisible until summoned." },
              { icon: <div style={{ width: "20px", height: "20px", border: "1.6px solid var(--accent)", borderRadius: "50%" }} />, title: "Minimal & calm", body: "Quiet motion. Quiet chrome. Full focus." },
            ].map((p) => (
              <div key={p.title} style={{ background: "#0b0c0f", padding: "28px 22px", display: "flex", flexDirection: "column", gap: "14px" }}>
                {p.icon}
                <div style={{ fontSize: "17px", fontWeight: 600, letterSpacing: "-0.01em" }}>{p.title}</div>
                <div style={{ fontSize: "13px", color: "var(--dim)", lineHeight: 1.45 }}>{p.body}</div>
              </div>
            ))}
          </div>
        </section>

        {/* THE FEEL */}
        <section id="feel" style={{ position: "relative", maxWidth: "1200px", margin: "0 auto", padding: "90px 32px", borderTop: "1px solid var(--bd)" }}>
          <div style={{ maxWidth: "780px" }}>
            <div style={{ fontFamily: mono, fontSize: "12px", letterSpacing: "0.28em", color: "var(--accent)", textTransform: "uppercase", marginBottom: "22px" }}>Feel &amp; performance — one goal</div>
            <h2 style={{ fontSize: "clamp(32px,4.5vw,52px)", fontWeight: 700, letterSpacing: "-0.035em", lineHeight: 1.05, marginBottom: "22px" }}>
              While you switch,
              <br />
              the rest of the world recedes.
            </h2>
            <p style={{ fontSize: "18px", color: "var(--dim)", lineHeight: 1.55 }}>
              ZenTab isn't really about its interface — it's about the focus it brings. Feel and performance are the same goal: a switch that stutters can't feel calm, and a switch that feels calm is, by definition, fast. So we judge every choice against both, and never brag about either.
            </p>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(2,1fr)", gap: "16px", marginTop: "46px" }}>
            {[
              { glyph: <div style={{ width: "14px", height: "14px", border: "1.5px solid var(--accent)", borderRadius: "4px" }} />, title: "Zero-friction, invisible", body: "Switching never breaks your flow. The tool gets out of the way the instant you're done — and asks for nothing when you're not using it." },
              { glyph: <div style={{ width: "14px", height: "14px", background: "var(--accent)", borderRadius: "4px" }} />, title: "Single-tasking by default", body: "The current task is the center of gravity. Each mode scopes tightly, so everything else feels put away rather than piled up." },
              { glyph: <div style={{ width: "16px", height: "6px", background: "var(--accent)", borderRadius: "3px" }} />, title: "Calm, not stimulating", body: "A soft 80–120ms fade at the monitor's real refresh rate. Quiet, unhurried motion — no jarring transitions, no loud chrome." },
              { glyph: <div style={{ width: "14px", height: "14px", borderRadius: "50%", border: "1.5px solid var(--accent)" }} />, title: "Attention, in the moment", body: "While you choose, the world behind dims and blurs. The choices step forward; everything else steps back until you've landed." },
            ].map((f) => (
              <div key={f.title} style={{ background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "20px", padding: "32px", display: "flex", gap: "20px", alignItems: "flex-start" }}>
                <div style={{ width: "38px", height: "38px", border: "1px solid var(--bd)", borderRadius: "11px", flex: "none", display: "flex", alignItems: "center", justifyContent: "center" }}>{f.glyph}</div>
                <div>
                  <h3 style={{ fontSize: "19px", fontWeight: 600, letterSpacing: "-0.01em", marginBottom: "7px" }}>{f.title}</h3>
                  <p style={{ fontSize: "14.5px", color: "var(--dim)", lineHeight: 1.5 }}>{f.body}</p>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* THREE MODES */}
        <section id="modes" style={{ position: "relative", maxWidth: "1200px", margin: "0 auto", padding: "90px 32px", borderTop: "1px solid var(--bd)" }}>
          <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between", flexWrap: "wrap", gap: "20px", marginBottom: "46px" }}>
            <div>
              <div style={{ fontFamily: mono, fontSize: "12px", letterSpacing: "0.28em", color: "var(--accent)", textTransform: "uppercase", marginBottom: "18px" }}>Three modes</div>
              <h2 style={{ fontSize: "clamp(32px,4.5vw,52px)", fontWeight: 700, letterSpacing: "-0.035em", lineHeight: 1.05 }}>
                Three modes.
                <br />
                Each does one thing, beautifully.
              </h2>
            </div>
            <p style={{ fontSize: "15px", color: "var(--dim)", maxWidth: "320px", lineHeight: 1.5 }}>We sweat the behavior so you never have to think about it. The one thing in your hands: which keys summon each mode.</p>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
            {/* mode 1 */}
            <div style={{ display: "grid", gridTemplateColumns: "54px 1fr 300px", gap: "28px", alignItems: "center", background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "22px", padding: "34px 36px" }}>
              <span style={{ fontFamily: mono, fontSize: "15px", color: "var(--accent)" }}>01</span>
              <div>
                <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "10px" }}>
                  <h3 style={{ fontSize: "26px", fontWeight: 600, letterSpacing: "-0.02em" }}>Everyday switch</h3>
                  <span style={{ fontFamily: mono, fontSize: "12px", color: "var(--dim)", border: "1px solid var(--bd)", borderRadius: "7px", padding: "5px 9px" }}>⌘ Tab</span>
                </div>
                <p style={{ fontSize: "16px", color: "var(--dim)", lineHeight: 1.5, maxWidth: "520px" }}>Every window on the current monitor and desktop. The one you reach for a hundred times a day.</p>
              </div>
              <div style={{ display: "flex", gap: "7px", justifyContent: "flex-end" }}>
                <div style={{ width: "54px", height: "42px", borderRadius: "8px", background: "rgba(255,255,255,0.04)", border: "1px solid var(--bd)" }} />
                <div style={{ width: "54px", height: "42px", borderRadius: "8px", background: "rgba(93,109,255,0.14)", border: "2px solid var(--accent)", boxShadow: "0 8px 22px rgba(93,109,255,0.25)" }} />
                <div style={{ width: "54px", height: "42px", borderRadius: "8px", background: "rgba(255,255,255,0.04)", border: "1px solid var(--bd)" }} />
                <div style={{ width: "54px", height: "42px", borderRadius: "8px", background: "rgba(255,255,255,0.04)", border: "1px solid var(--bd)" }} />
              </div>
            </div>
            {/* mode 2 */}
            <div style={{ display: "grid", gridTemplateColumns: "54px 1fr 300px", gap: "28px", alignItems: "center", background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "22px", padding: "34px 36px" }}>
              <span style={{ fontFamily: mono, fontSize: "15px", color: "var(--accent)" }}>02</span>
              <div>
                <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "10px" }}>
                  <h3 style={{ fontSize: "26px", fontWeight: 600, letterSpacing: "-0.02em" }}>Current-app windows</h3>
                  <span style={{ fontFamily: mono, fontSize: "12px", color: "var(--dim)", border: "1px solid var(--bd)", borderRadius: "7px", padding: "5px 9px" }}>⌘ `</span>
                </div>
                <p style={{ fontSize: "16px", color: "var(--dim)", lineHeight: 1.5, maxWidth: "520px" }}>Every window of the active app — gathered from other desktops, other monitors, even minimized.</p>
              </div>
              <div style={{ display: "flex", gap: "7px", justifyContent: "flex-end", alignItems: "center" }}>
                <div style={{ display: "flex", flexDirection: "column", gap: "5px" }}>
                  <div style={{ width: "40px", height: "18px", borderRadius: "5px", background: "rgba(255,255,255,0.04)", border: "1px solid var(--bd)" }} />
                  <div style={{ width: "40px", height: "18px", borderRadius: "5px", background: "rgba(255,255,255,0.04)", border: "1px solid var(--bd)" }} />
                </div>
                <span style={{ color: "var(--faint)", fontSize: "18px" }}>→</span>
                <div style={{ display: "flex", gap: "5px" }}>
                  <div style={{ width: "44px", height: "42px", borderRadius: "8px", background: "rgba(124,140,255,0.16)", border: "2px solid var(--accent)" }} />
                  <div style={{ width: "44px", height: "42px", borderRadius: "8px", background: "rgba(124,140,255,0.06)", border: "1px solid var(--bd)" }} />
                </div>
              </div>
            </div>
            {/* mode 3 */}
            <div style={{ display: "grid", gridTemplateColumns: "54px 1fr 300px", gap: "28px", alignItems: "center", background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "22px", padding: "34px 36px" }}>
              <span style={{ fontFamily: mono, fontSize: "15px", color: "var(--accent)" }}>03</span>
              <div>
                <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "10px" }}>
                  <h3 style={{ fontSize: "26px", fontWeight: 600, letterSpacing: "-0.02em" }}>Global escape hatch</h3>
                  <span style={{ fontFamily: mono, fontSize: "12px", color: "var(--dim)", border: "1px solid var(--bd)", borderRadius: "7px", padding: "5px 9px" }}>⌥ Tab</span>
                </div>
                <p style={{ fontSize: "16px", color: "var(--dim)", lineHeight: 1.5, maxWidth: "520px" }}>Everything, everywhere. The "I lost something" valve — for when a window is hiding and you just need it back.</p>
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: "5px", justifyContent: "flex-end" }}>
                {[0, 1, 2, 3, 4, 5, 6, 7].map((n) => (
                  <div key={n} style={{ height: "26px", borderRadius: "6px", background: n === 2 ? "rgba(93,109,255,0.16)" : "rgba(255,255,255,0.04)", border: n === 2 ? "2px solid var(--accent)" : "1px solid var(--bd)" }} />
                ))}
              </div>
            </div>
          </div>
        </section>

        {/* STABLE ORDER + TWO ACTIONS */}
        <section style={{ position: "relative", maxWidth: "1200px", margin: "0 auto", padding: "0 32px 90px" }}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "16px" }}>
            <div style={{ background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "22px", padding: "38px" }}>
              <h3 style={{ fontSize: "24px", fontWeight: 600, letterSpacing: "-0.02em", marginBottom: "12px" }}>Stable order builds muscle memory</h3>
              <p style={{ fontSize: "15px", color: "var(--dim)", lineHeight: 1.55, marginBottom: "26px" }}>Tiles never reshuffle by recency. Slack is always 4th, so your hand learns the path and stops looking. The overlay becomes a reflex, not a decision.</p>
              <div style={{ display: "flex", gap: "8px" }}>
                {["1", "2", "3", "4 ·#", "5"].map((n, i) => (
                  <div key={n} style={{ flex: 1, textAlign: "center", background: i === 3 ? "rgba(93,109,255,0.16)" : "rgba(255,255,255,0.03)", border: i === 3 ? "1px solid var(--accent)" : "1px solid var(--bd)", borderRadius: "10px", padding: "14px 0", fontFamily: mono, fontSize: "12px", color: i === 3 ? "#fff" : "var(--faint)" }}>{n}</div>
                ))}
              </div>
            </div>
            <div style={{ background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "22px", padding: "38px" }}>
              <h3 style={{ fontSize: "24px", fontWeight: 600, letterSpacing: "-0.02em", marginBottom: "12px" }}>Close or quit, right where you are</h3>
              <p style={{ fontSize: "15px", color: "var(--dim)", lineHeight: 1.55, marginBottom: "26px" }}>Tidy up mid-switch — close a window or quit an app without ever leaving the overlay.</p>
              <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
                <div style={{ display: "flex", alignItems: "center", gap: "14px", background: "rgba(255,255,255,0.03)", border: "1px solid var(--bd)", borderRadius: "12px", padding: "15px 18px" }}>
                  <kbd style={{ fontFamily: mono, fontSize: "14px", background: "var(--cardhi)", border: "1px solid var(--bdhi)", borderBottomWidth: "2px", borderRadius: "8px", padding: "7px 12px" }}>W</kbd>
                  <span style={{ fontSize: "15px", color: "var(--tx)" }}>Close the focused window</span>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: "14px", background: "rgba(255,255,255,0.03)", border: "1px solid var(--bd)", borderRadius: "12px", padding: "15px 18px" }}>
                  <kbd style={{ fontFamily: mono, fontSize: "14px", background: "var(--cardhi)", border: "1px solid var(--bdhi)", borderBottomWidth: "2px", borderRadius: "8px", padding: "7px 13px" }}>Q</kbd>
                  <span style={{ fontSize: "15px", color: "var(--tx)" }}>Quit the focused app</span>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* CONFIG */}
        <section id="config" style={{ position: "relative", maxWidth: "1200px", margin: "0 auto", padding: "90px 32px", borderTop: "1px solid var(--bd)" }}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "54px", alignItems: "center" }}>
            <div>
              <div style={{ fontFamily: mono, fontSize: "12px", letterSpacing: "0.28em", color: "var(--accent)", textTransform: "uppercase", marginBottom: "22px" }}>Calm by design</div>
              <h2 style={{ fontSize: "clamp(32px,4.5vw,52px)", fontWeight: 700, letterSpacing: "-0.035em", lineHeight: 1.05, marginBottom: "22px" }}>
                No settings.
                <br />
                On purpose.
              </h2>
              <p style={{ fontSize: "17px", color: "var(--dim)", lineHeight: 1.55, marginBottom: "18px" }}>Every setting is a small decision, and decisions pull you out of your flow — so ZenTab has none. We make the calls and keep you on one clear path. The calm comes from having nothing to fiddle with.</p>
              <p style={{ fontSize: "15px", color: "var(--faint)", lineHeight: 1.55 }}>The one file that does exist is just for the keys that summon each mode. Open it once, then forget it's there.</p>
            </div>
            <div style={{ background: "#0e0f14", border: "1px solid var(--bd)", borderRadius: "18px", overflow: "hidden", boxShadow: "0 30px 80px rgba(0,0,0,0.45)" }}>
              <div style={{ display: "flex", alignItems: "center", gap: "8px", padding: "13px 16px", borderBottom: "1px solid var(--bd)", background: "rgba(255,255,255,0.02)" }}>
                <div style={{ width: "10px", height: "10px", borderRadius: "50%", background: "#ff5f57" }} />
                <div style={{ width: "10px", height: "10px", borderRadius: "50%", background: "#febc2e" }} />
                <div style={{ width: "10px", height: "10px", borderRadius: "50%", background: "#28c840" }} />
                <span style={{ fontFamily: mono, fontSize: "11.5px", color: "var(--faint)", marginLeft: "8px" }}>~/.zentab.toml</span>
              </div>
              <pre style={{ fontFamily: mono, fontSize: "13.5px", lineHeight: 1.85, padding: "22px 24px", margin: 0, color: "var(--dim)", overflowX: "auto" }}>
                <span style={{ color: "var(--faint)" }}># great defaults out of the box —</span>
                {"\n"}
                <span style={{ color: "var(--faint)" }}># tune the keys to your hands.</span>
                {"\n\n[triggers]\neveryday   = "}
                <span style={{ color: "#5d6dff" }}>"cmd+tab"</span>
                {"\ncurrent_app = "}
                <span style={{ color: "#5d6dff" }}>"cmd+grave"</span>
                {"\nglobal     = "}
                <span style={{ color: "#5d6dff" }}>"opt+tab"</span>
                {"\n\n[overlay]\ntheme = "}
                <span style={{ color: "#5d6dff" }}>"dark"</span>
                {"   "}
                <span style={{ color: "var(--faint)" }}># dark | light</span>
              </pre>
            </div>
          </div>
        </section>

        {/* FREE FOREVER */}
        <section id="free" style={{ position: "relative", maxWidth: "1200px", margin: "0 auto", padding: "90px 32px", borderTop: "1px solid var(--bd)" }}>
          <div style={{ position: "relative", background: "linear-gradient(160deg,#15171f,#0d0e13)", border: "1px solid var(--bd)", borderRadius: "26px", padding: "70px 48px", textAlign: "center", overflow: "hidden" }}>
            <div style={{ position: "absolute", top: "-100px", left: "50%", transform: "translateX(-50%)", width: "500px", height: "300px", background: "radial-gradient(circle,rgba(93,109,255,0.14),transparent 70%)", filter: "blur(10px)" }} />
            <div style={{ position: "relative", zIndex: 2 }}>
              <div style={{ fontFamily: mono, fontSize: "12px", letterSpacing: "0.28em", color: "var(--accent)", textTransform: "uppercase", marginBottom: "24px" }}>Free for everyone</div>
              <h2 style={{ fontSize: "clamp(40px,6vw,72px)", fontWeight: 700, letterSpacing: "-0.04em", lineHeight: 1, marginBottom: "24px" }}>Free. Forever.</h2>
              <p style={{ fontSize: "18px", color: "var(--dim)", lineHeight: 1.55, maxWidth: "560px", margin: "0 auto 36px" }}>A calmer way to switch should belong to everyone. Download it, keep it, pass it to a friend — it's yours, with nothing to buy and nothing to renew.</p>
              <div style={{ display: "flex", gap: "26px", justifyContent: "center", flexWrap: "wrap", fontFamily: mono, fontSize: "12px", color: "var(--faint)" }}>
                {["Yours to keep", "Private by default", "Two native apps, one feel"].map((t) => (
                  <span key={t} style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                    <span style={{ width: "5px", height: "5px", borderRadius: "50%", background: "#5bd6a0" }} />
                    {t}
                  </span>
                ))}
              </div>
            </div>
          </div>
        </section>

        {/* DOWNLOAD */}
        <section id="download" style={{ position: "relative", maxWidth: "1200px", margin: "0 auto", padding: "30px 32px 100px" }}>
          <div style={{ textAlign: "center", marginBottom: "40px" }}>
            <h2 style={{ fontSize: "clamp(30px,4vw,46px)", fontWeight: 700, letterSpacing: "-0.035em", marginBottom: "14px" }}>Get ZenTab</h2>
            <p style={{ fontSize: "16px", color: "var(--dim)" }}>One product. Two native apps. The same calm on both.</p>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "16px", maxWidth: "780px", margin: "0 auto" }}>
            <a href="#download" className="zt-card-hover" style={{ background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "20px", padding: "34px", display: "flex", flexDirection: "column", gap: "6px" }}>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "14px" }}>
                <span style={{ fontSize: "21px", fontWeight: 600, letterSpacing: "-0.02em" }}>macOS</span>
                <span style={{ fontFamily: mono, fontSize: "11px", color: "#5bd6a0", border: "1px solid rgba(91,214,160,0.3)", borderRadius: "6px", padding: "3px 8px" }}>Available</span>
              </div>
              <span style={{ fontSize: "14px", fontWeight: 600, background: "var(--tx)", color: "#0b0c0f", borderRadius: "10px", padding: "12px", textAlign: "center" }}>Download · v1.0</span>
              <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)", marginTop: "8px" }}>Universal · macOS 13+ · 4.2 MB</span>
            </a>
            <a href="#download" className="zt-card-hover" style={{ background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "20px", padding: "34px", display: "flex", flexDirection: "column", gap: "6px" }}>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "14px" }}>
                <span style={{ fontSize: "21px", fontWeight: 600, letterSpacing: "-0.02em" }}>Windows</span>
                <span style={{ fontFamily: mono, fontSize: "11px", color: "#5bd6a0", border: "1px solid rgba(91,214,160,0.3)", borderRadius: "6px", padding: "3px 8px" }}>Available</span>
              </div>
              <span style={{ fontSize: "14px", fontWeight: 600, background: "rgba(255,255,255,0.06)", border: "1px solid var(--bdhi)", color: "var(--tx)", borderRadius: "10px", padding: "12px", textAlign: "center" }}>Download · v1.0</span>
              <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)", marginTop: "8px" }}>Windows 10 / 11 · 5.1 MB</span>
            </a>
          </div>
        </section>

        {/* FOOTER */}
        <footer style={{ position: "relative", borderTop: "1px solid var(--bd)" }}>
          <div style={{ maxWidth: "1200px", margin: "0 auto", padding: "44px 32px", display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "24px" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "11px" }}>
              <div style={{ position: "relative", width: "24px", height: "24px" }}>
                <div style={{ position: "absolute", inset: 0, border: "1.5px solid var(--bdhi)", borderRadius: "7px" }} />
                <div style={{ position: "absolute", left: "7px", top: "7px", width: "17px", height: "17px", background: "linear-gradient(145deg,#7282ff,#5160ff)", borderRadius: "6px" }} />
              </div>
              <span style={{ fontWeight: 600, fontSize: "16px", letterSpacing: "-0.02em" }}>ZenTab</span>
              <span style={{ fontSize: "14px", color: "var(--faint)", marginLeft: "8px" }}>The world recedes for a moment.</span>
            </div>
            <div style={{ display: "flex", gap: "24px", fontSize: "13.5px", color: "var(--dim)" }}>
              <a href="#feel" className="zt-link">The feel</a>
              <a href="#modes" className="zt-link">Modes</a>
              <a href="#config" className="zt-link">Config</a>
              <Link to="/overlay" className="zt-link">Overlay</Link>
              <Link to="/brand" className="zt-link">Brand</Link>
            </div>
            <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)", letterSpacing: "0.08em" }}>FREE FOREVER · © 2026</span>
          </div>
        </footer>
      </div>
    );
  }
}
