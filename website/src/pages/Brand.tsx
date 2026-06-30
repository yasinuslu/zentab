import { Component } from "react";
import type { CSSProperties, ReactNode } from "react";
import { Link } from "react-router-dom";

const mono = "'JetBrains Mono',monospace";

type BrandThumbType = "editor" | "darkui" | "browser";

interface Swatch {
  name: string;
  hex: string;
  bg: string;
  role: string;
}

interface BrandState {
  copiedHex: string | null;
  active: number;
}

function bar(w: string, c?: string, o?: number): ReactNode {
  return <div style={{ height: "3px", borderRadius: "2px", width: w, background: c ?? "rgba(255,255,255,0.5)", opacity: o ?? 1 }} />;
}

// Brand-page thumbnail (its own proportions, kept faithful to the source).
function thumbInner(type: BrandThumbType): ReactNode {
  if (type === "editor") {
    return (
      <div style={{ position: "absolute", inset: 0, background: "#14151b", display: "flex" }}>
        <div style={{ width: "30%", padding: "9px 7px", display: "flex", flexDirection: "column", gap: "5px", borderRight: "1px solid rgba(255,255,255,0.05)" }}>
          {bar("70%", "rgba(255,255,255,0.32)")}
          {bar("85%", "rgba(255,255,255,0.18)")}
          {bar("55%", "rgba(255,255,255,0.18)")}
          {bar("78%", "rgba(255,255,255,0.18)")}
          {bar("60%", "rgba(255,255,255,0.18)")}
          {bar("80%", "rgba(255,255,255,0.18)")}
        </div>
        <div style={{ flex: 1, padding: "9px 9px", display: "flex", flexDirection: "column", gap: "5px" }}>
          {bar("40%", "#5d6dff", 0.9)}
          {bar("88%", "rgba(255,255,255,0.16)")}
          {bar("72%", "rgba(255,255,255,0.16)")}
          {bar("50%", "#5bd6a0", 0.7)}
          {bar("82%", "rgba(255,255,255,0.16)")}
          {bar("64%", "rgba(255,255,255,0.16)")}
          {bar("35%", "#e0a05b", 0.7)}
        </div>
      </div>
    );
  }
  if (type === "darkui") {
    return (
      <div style={{ position: "absolute", inset: 0, background: "#0c0d12", padding: "12px", display: "flex", flexDirection: "column", gap: "8px", alignItems: "center", justifyContent: "center" }}>
        <div style={{ width: "62%", height: "34px", borderRadius: "7px", background: "rgba(255,255,255,0.04)", border: "1px solid rgba(93,109,255,0.4)", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <div style={{ width: "26px", height: "12px", borderRadius: "4px", background: "linear-gradient(145deg,#7282ff,#5160ff)" }} />
        </div>
        <div style={{ display: "flex", gap: "6px" }}>
          <div style={{ width: "30px", height: "8px", borderRadius: "3px", background: "rgba(255,255,255,0.1)" }} />
          <div style={{ width: "20px", height: "8px", borderRadius: "3px", background: "rgba(255,255,255,0.1)" }} />
        </div>
      </div>
    );
  }
  // browser (light)
  return (
    <div style={{ position: "absolute", inset: 0, background: "#f4f2ec" }}>
      <div style={{ height: "16px", background: "#e7e3d8", display: "flex", alignItems: "center", gap: "4px", padding: "0 8px" }}>
        <div style={{ width: "5px", height: "5px", borderRadius: "50%", background: "#c8c2b2" }} />
        <div style={{ width: "5px", height: "5px", borderRadius: "50%", background: "#c8c2b2" }} />
      </div>
      <div style={{ display: "flex", padding: "11px 12px", gap: "12px" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "6px" }}>
          {bar("80%", "#33312b")}
          {bar("90%", "rgba(0,0,0,0.18)")}
          {bar("65%", "rgba(0,0,0,0.18)")}
          {bar("72%", "rgba(0,0,0,0.18)")}
        </div>
        <div style={{ width: "38%", height: "62px", borderRadius: "6px", background: "#1c1b18" }} />
      </div>
    </div>
  );
}

export default class Brand extends Component<Record<string, never>, BrandState> {
  state: BrandState = { copiedHex: null, active: 1 };
  private _t?: ReturnType<typeof setInterval>;
  private _c?: ReturnType<typeof setTimeout>;

  componentDidMount() {
    this._t = setInterval(() => {
      this.setState((s) => ({ active: (s.active + 1) % 3 }));
    }, 1700);
  }
  componentWillUnmount() {
    clearInterval(this._t);
    clearTimeout(this._c);
  }

  copyHex(hex: string) {
    try {
      if (navigator.clipboard) navigator.clipboard.writeText(hex);
    } catch {
      /* clipboard not available */
    }
    this.setState({ copiedHex: hex });
    clearTimeout(this._c);
    this._c = setTimeout(() => this.setState({ copiedHex: null }), 1100);
  }

  render() {
    const swatches: Swatch[] = [
      { name: "Void", hex: "#0B0C0F", bg: "#0B0C0F", role: "Primary background" },
      { name: "Slate", hex: "#101218", bg: "#101218", role: "Raised surface" },
      { name: "Glass", hex: "rgba(255,255,255,.05)", bg: "linear-gradient(145deg,rgba(255,255,255,.07),rgba(255,255,255,.02))", role: "Overlay tile" },
      { name: "Electric", hex: "#5D6DFF", bg: "linear-gradient(145deg,#7282ff,#5160ff)", role: "Accent · the focus" },
      { name: "Ice", hex: "#ECEDF1", bg: "#ECEDF1", role: "Primary text" },
      { name: "Mist", hex: "#9B9EA9", bg: "#9B9EA9", role: "Secondary text" },
      { name: "Smoke", hex: "#5E616C", bg: "#5E616C", role: "Faint · labels" },
      { name: "Hairline", hex: "rgba(255,255,255,.075)", bg: "rgba(255,255,255,.10)", role: "Borders · dividers" },
    ];

    const wins: { title: string; icon: string; letter: string; type: BrandThumbType }[] = [
      { title: "zentab — BRANDING.md", icon: "#3b3e47", letter: "Z", type: "editor" },
      { title: "Design", icon: "#e0563a", letter: "✳", type: "darkui" },
      { title: "Zen Browser", icon: "#7c8cff", letter: "z", type: "browser" },
    ];
    const active = this.state.active;

    const pill: CSSProperties = { fontFamily: mono, fontSize: "12px", letterSpacing: "0.04em", color: "var(--dim)", textDecoration: "none", border: "1px solid var(--bd)", borderRadius: "999px", padding: "9px 16px" };
    const card: CSSProperties = { background: "var(--card)", border: "1px solid var(--bd)", borderRadius: "20px" };
    const sectionLabel: CSSProperties = { fontFamily: mono, fontSize: "13px", color: "var(--accent)", letterSpacing: "0.1em" };

    const root: CSSProperties = {
      ["--bg" as string]: "#0b0c0f",
      ["--bg2" as string]: "#101218",
      ["--card" as string]: "rgba(255,255,255,0.025)",
      ["--cardhi" as string]: "rgba(255,255,255,0.05)",
      ["--bd" as string]: "rgba(255,255,255,0.075)",
      ["--bdhi" as string]: "rgba(255,255,255,0.14)",
      ["--tx" as string]: "#ECEDF1",
      ["--dim" as string]: "#9b9ea9",
      ["--faint" as string]: "#5e616c",
      ["--accent" as string]: "#5d6dff",
      ["--accentdim" as string]: "rgba(93,109,255,0.16)",
      fontFamily: "'Schibsted Grotesk',sans-serif",
      color: "var(--tx)",
      background: "radial-gradient(140% 90% at 80% -10%, #14161f 0%, #0b0c0f 55%)",
      minHeight: "100vh",
      overflowX: "hidden",
      position: "relative",
    };

    return (
      <div style={root}>
        <div style={{ position: "fixed", top: "-200px", right: "-150px", width: "620px", height: "620px", borderRadius: "50%", background: "radial-gradient(circle, rgba(93,109,255,0.14) 0%, rgba(93,109,255,0) 65%)", filter: "blur(20px)", pointerEvents: "none", animation: "ztDrift 16s ease-in-out infinite", zIndex: 0 }} />

        {/* TOP BAR */}
        <div style={{ position: "relative", zIndex: 3, maxWidth: "1160px", margin: "0 auto", padding: "30px 40px 0", display: "flex", alignItems: "center", justifyContent: "space-between", animation: "ztFade .8s ease" }}>
          <Link to="/" style={{ display: "flex", alignItems: "center", gap: "11px" }}>
            <div style={{ position: "relative", width: "26px", height: "26px", flex: "none" }}>
              <div style={{ position: "absolute", inset: 0, border: "1.5px solid var(--bdhi)", borderRadius: "7px" }} />
              <div style={{ position: "absolute", left: "8px", top: "8px", width: "18px", height: "18px", background: "var(--accent)", borderRadius: "6px", boxShadow: "0 4px 14px rgba(93,109,255,0.5)" }} />
            </div>
            <span style={{ fontWeight: 600, letterSpacing: "-0.02em", fontSize: "17px" }}>ZenTab</span>
          </Link>
          <span style={{ fontFamily: mono, fontSize: "11px", letterSpacing: "0.18em", color: "var(--faint)", textTransform: "uppercase" }}>Brand System — v1.0</span>
        </div>

        {/* HERO */}
        <section style={{ position: "relative", zIndex: 2, maxWidth: "1160px", margin: "0 auto", padding: "118px 40px 90px" }}>
          <div style={{ fontFamily: mono, fontSize: "12px", letterSpacing: "0.32em", color: "var(--accent)", textTransform: "uppercase", marginBottom: "34px", animation: "ztUp .7s ease" }}>Identity</div>
          <div style={{ display: "flex", alignItems: "center", gap: "34px", marginBottom: "38px", animation: "ztUp .8s .05s ease" }}>
            <div style={{ position: "relative", width: "96px", height: "96px", flex: "none" }}>
              <div style={{ position: "absolute", inset: 0, border: "2px solid var(--bdhi)", borderRadius: "24px" }} />
              <div style={{ position: "absolute", left: "30px", top: "30px", width: "66px", height: "66px", background: "linear-gradient(145deg,#7282ff,#5160ff)", borderRadius: "20px", boxShadow: "0 18px 50px rgba(93,109,255,0.45)" }} />
            </div>
            <h1 style={{ fontSize: "108px", fontWeight: 700, letterSpacing: "-0.045em", lineHeight: 0.92 }}>ZenTab</h1>
          </div>
          <p style={{ fontSize: "30px", fontWeight: 500, letterSpacing: "-0.02em", lineHeight: 1.22, maxWidth: "720px", color: "var(--tx)", animation: "ztUp .8s .12s ease" }}>Window switching that feels instant.</p>
          <p style={{ fontSize: "18px", lineHeight: 1.55, maxWidth: "560px", color: "var(--dim)", marginTop: "18px", animation: "ztUp .8s .18s ease" }}>One keystroke. Three modes. Zero perceptible lag. A switcher that picks one right behavior and deletes the knob.</p>
          <div style={{ display: "flex", gap: "10px", marginTop: "40px", animation: "ztUp .8s .24s ease", flexWrap: "wrap" }}>
            <a href="#logo" style={pill}>01 — Logo</a>
            <a href="#color" style={pill}>02 — Color</a>
            <a href="#type" style={pill}>03 — Type</a>
            <a href="#voice" style={pill}>04 — Voice</a>
            <a href="#overlay" style={{ ...pill, color: "var(--accent)", border: "1px solid rgba(93,109,255,0.4)" }}>05 — In use</a>
          </div>
        </section>

        {/* 01 LOGO */}
        <section id="logo" style={{ position: "relative", zIndex: 2, maxWidth: "1160px", margin: "0 auto", padding: "64px 40px", borderTop: "1px solid var(--bd)" }}>
          <div style={{ display: "flex", alignItems: "baseline", gap: "18px", marginBottom: "48px" }}>
            <span style={sectionLabel}>01</span>
            <h2 style={{ fontSize: "38px", fontWeight: 600, letterSpacing: "-0.03em" }}>The mark</h2>
            <span style={{ fontSize: "16px", color: "var(--faint)", marginLeft: "auto", maxWidth: "300px", textAlign: "right" }}>A focused tile, framed. Calm holding the active window.</span>
          </div>

          <div style={{ display: "grid", gridTemplateColumns: "1.15fr .85fr", gap: "18px" }}>
            <div style={{ ...card, padding: "48px", display: "flex", alignItems: "center", justifyContent: "center", position: "relative", minHeight: "360px", overflow: "hidden" }}>
              <div style={{ position: "absolute", inset: 0, backgroundImage: "linear-gradient(var(--bd) 1px,transparent 1px),linear-gradient(90deg,var(--bd) 1px,transparent 1px)", backgroundSize: "32px 32px", opacity: 0.35 }} />
              <div style={{ position: "relative", width: "160px", height: "160px" }}>
                <div style={{ position: "absolute", inset: 0, border: "2.5px solid var(--bdhi)", borderRadius: "36px" }} />
                <div style={{ position: "absolute", left: "50px", top: "50px", width: "110px", height: "110px", background: "linear-gradient(145deg,#7282ff,#5160ff)", borderRadius: "30px", boxShadow: "0 22px 60px rgba(93,109,255,0.45)" }} />
                <div style={{ position: "absolute", left: "50px", top: "-22px", bottom: "-22px", width: 0, borderLeft: "1px dashed rgba(93,109,255,0.45)" }} />
                <div style={{ position: "absolute", top: "50px", left: "-22px", right: "-22px", height: 0, borderTop: "1px dashed rgba(93,109,255,0.45)" }} />
              </div>
              <span style={{ position: "absolute", bottom: "18px", left: "20px", fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>grid 8 · radius 30 · offset φ</span>
            </div>
            <div style={{ ...card, padding: "36px", display: "flex", flexDirection: "column", justifyContent: "space-between", minHeight: "360px" }}>
              <div>
                <div style={{ fontFamily: mono, fontSize: "11px", letterSpacing: "0.14em", color: "var(--faint)", textTransform: "uppercase", marginBottom: "14px" }}>What it means</div>
                <div style={{ fontSize: "19px", fontWeight: 500, letterSpacing: "-0.01em", lineHeight: 1.4, color: "var(--tx)" }}>The outer frame is the switcher — steady, always there. The filled tile is the window in focus.</div>
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: "14px", borderTop: "1px solid var(--bd)", paddingTop: "22px" }}>
                <div style={{ display: "flex", alignItems: "flex-start", gap: "12px" }}>
                  <div style={{ width: "18px", height: "18px", border: "1.6px solid var(--bdhi)", borderRadius: "5px", flex: "none", marginTop: "1px" }} />
                  <span style={{ fontSize: "14px", color: "var(--dim)", lineHeight: 1.4 }}>The frame never moves — that's the spatial muscle memory.</span>
                </div>
                <div style={{ display: "flex", alignItems: "flex-start", gap: "12px" }}>
                  <div style={{ width: "18px", height: "18px", background: "linear-gradient(145deg,#7282ff,#5160ff)", borderRadius: "5px", flex: "none", marginTop: "1px" }} />
                  <span style={{ fontSize: "14px", color: "var(--dim)", lineHeight: 1.4 }}>Only the focus is accent — one held note, never two.</span>
                </div>
              </div>
            </div>
          </div>

          {/* lockups */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: "18px", marginTop: "18px" }}>
            <div style={{ ...card, padding: "38px", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "22px", minHeight: "200px" }}>
              <div style={{ display: "flex", alignItems: "center", gap: "16px" }}>
                <div style={{ position: "relative", width: "42px", height: "42px", flex: "none" }}>
                  <div style={{ position: "absolute", inset: 0, border: "2px solid var(--bdhi)", borderRadius: "11px" }} />
                  <div style={{ position: "absolute", left: "13px", top: "13px", width: "29px", height: "29px", background: "linear-gradient(145deg,#7282ff,#5160ff)", borderRadius: "9px" }} />
                </div>
                <span style={{ fontWeight: 600, fontSize: "30px", letterSpacing: "-0.03em" }}>ZenTab</span>
              </div>
              <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>primary lockup</span>
            </div>
            <div style={{ ...card, padding: "38px", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "22px", minHeight: "200px" }}>
              <div style={{ position: "relative", width: "64px", height: "64px", flex: "none" }}>
                <div style={{ position: "absolute", inset: 0, border: "2.5px solid var(--bdhi)", borderRadius: "17px" }} />
                <div style={{ position: "absolute", left: "20px", top: "20px", width: "44px", height: "44px", background: "linear-gradient(145deg,#7282ff,#5160ff)", borderRadius: "13px" }} />
              </div>
              <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>symbol only</span>
            </div>
            <div style={{ background: "#ECEDF1", border: "1px solid var(--bd)", borderRadius: "20px", padding: "38px", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "22px", minHeight: "200px" }}>
              <div style={{ display: "flex", alignItems: "center", gap: "16px" }}>
                <div style={{ position: "relative", width: "42px", height: "42px", flex: "none" }}>
                  <div style={{ position: "absolute", inset: 0, border: "2px solid #c3c5cf", borderRadius: "11px" }} />
                  <div style={{ position: "absolute", left: "13px", top: "13px", width: "29px", height: "29px", background: "linear-gradient(145deg,#5160ff,#4250f5)", borderRadius: "9px" }} />
                </div>
                <span style={{ fontWeight: 600, fontSize: "30px", letterSpacing: "-0.03em", color: "#0b0c0f" }}>ZenTab</span>
              </div>
              <span style={{ fontFamily: mono, fontSize: "11px", color: "#9a9ca6" }}>on light</span>
            </div>
          </div>

          {/* app icon + menu glyph */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: "18px", marginTop: "18px" }}>
            <div style={{ ...card, padding: "32px", display: "flex", flexDirection: "column", alignItems: "center", gap: "18px" }}>
              <div style={{ position: "relative", width: "88px", height: "88px", borderRadius: "22px", background: "linear-gradient(160deg,#1a1d28,#0d0e13)", border: "1px solid var(--bdhi)", display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 14px 40px rgba(0,0,0,0.5)" }}>
                <div style={{ position: "relative", width: "48px", height: "48px" }}>
                  <div style={{ position: "absolute", inset: 0, border: "2px solid rgba(255,255,255,0.28)", borderRadius: "13px" }} />
                  <div style={{ position: "absolute", left: "15px", top: "15px", width: "33px", height: "33px", background: "linear-gradient(145deg,#7282ff,#5160ff)", borderRadius: "10px", boxShadow: "0 6px 18px rgba(93,109,255,0.6)" }} />
                </div>
              </div>
              <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>app icon</span>
            </div>
            <div style={{ ...card, padding: "32px", display: "flex", flexDirection: "column", alignItems: "center", gap: "18px" }}>
              <div style={{ width: "88px", height: "88px", borderRadius: "18px", background: "#16181f", display: "flex", alignItems: "center", justifyContent: "center" }}>
                <div style={{ position: "relative", width: "22px", height: "22px" }}>
                  <div style={{ position: "absolute", inset: 0, border: "1.6px solid var(--dim)", borderRadius: "6px" }} />
                  <div style={{ position: "absolute", left: "7px", top: "7px", width: "15px", height: "15px", background: "var(--dim)", borderRadius: "5px" }} />
                </div>
              </div>
              <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>menu-bar glyph</span>
            </div>
            <div style={{ ...card, padding: "32px", display: "flex", flexDirection: "column", alignItems: "center", gap: "18px", justifyContent: "center" }}>
              <div style={{ position: "relative", width: "88px", height: "88px" }}>
                <div style={{ position: "absolute", inset: 0, border: "2px solid var(--accent)", borderRadius: "22px" }} />
                <div style={{ position: "absolute", left: "28px", top: "28px", width: "60px", height: "60px", background: "none", border: "2px solid var(--accent)", borderRadius: "16px" }} />
              </div>
              <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>mono / stroke</span>
            </div>
            <div style={{ ...card, padding: "24px", display: "flex", flexDirection: "column", justifyContent: "center", gap: "12px" }}>
              <div style={{ fontFamily: mono, fontSize: "11px", letterSpacing: "0.14em", color: "var(--faint)", textTransform: "uppercase" }}>Clear space</div>
              <div style={{ fontSize: "14px", color: "var(--dim)", lineHeight: 1.5 }}>Keep the mark's own height of padding on every side. Never recolor the frame.</div>
            </div>
          </div>
        </section>

        {/* 02 COLOR */}
        <section id="color" style={{ position: "relative", zIndex: 2, maxWidth: "1160px", margin: "0 auto", padding: "64px 40px", borderTop: "1px solid var(--bd)" }}>
          <div style={{ display: "flex", alignItems: "baseline", gap: "18px", marginBottom: "48px" }}>
            <span style={sectionLabel}>02</span>
            <h2 style={{ fontSize: "38px", fontWeight: 600, letterSpacing: "-0.03em" }}>Color</h2>
            <span style={{ fontSize: "16px", color: "var(--faint)", marginLeft: "auto", maxWidth: "320px", textAlign: "right" }}>Near-black, cooled. One electric accent, used like a single held note.</span>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: "14px" }}>
            {swatches.map((sw) => {
              const copied = this.state.copiedHex === sw.hex;
              return (
                <div key={sw.name} className="zt-swatch" onClick={() => this.copyHex(sw.hex)} style={{ cursor: "pointer", border: "1px solid var(--bd)", borderRadius: "18px", overflow: "hidden", background: "var(--card)" }}>
                  <div style={{ height: "128px", background: sw.bg, position: "relative" }}>
                    {copied && (
                      <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", fontFamily: mono, fontSize: "12px", letterSpacing: "0.1em", background: "rgba(0,0,0,0.5)", color: "#fff" }}>copied</div>
                    )}
                  </div>
                  <div style={{ padding: "14px 15px 16px" }}>
                    <div style={{ fontSize: "14px", fontWeight: 600, letterSpacing: "-0.01em", marginBottom: "3px" }}>{sw.name}</div>
                    <div style={{ fontFamily: mono, fontSize: "12px", color: "var(--dim)" }}>{sw.hex}</div>
                    <div style={{ fontSize: "12px", color: "var(--faint)", marginTop: "8px", lineHeight: 1.4 }}>{sw.role}</div>
                  </div>
                </div>
              );
            })}
          </div>
          <div style={{ marginTop: "14px", ...card, borderRadius: "18px", padding: "22px 24px", display: "flex", alignItems: "center", gap: "24px", flexWrap: "wrap" }}>
            <span style={{ fontFamily: mono, fontSize: "11px", letterSpacing: "0.14em", color: "var(--faint)", textTransform: "uppercase" }}>Rule</span>
            <span style={{ fontSize: "15px", color: "var(--dim)" }}>Accent ≤ 8% of any surface. It marks the one thing in focus — the selected window — and nothing else.</span>
          </div>
        </section>

        {/* 03 TYPE */}
        <section id="type" style={{ position: "relative", zIndex: 2, maxWidth: "1160px", margin: "0 auto", padding: "64px 40px", borderTop: "1px solid var(--bd)" }}>
          <div style={{ display: "flex", alignItems: "baseline", gap: "18px", marginBottom: "48px" }}>
            <span style={sectionLabel}>03</span>
            <h2 style={{ fontSize: "38px", fontWeight: 600, letterSpacing: "-0.03em" }}>Type</h2>
            <span style={{ fontSize: "16px", color: "var(--faint)", marginLeft: "auto", maxWidth: "320px", textAlign: "right" }}>A precise grotesque for everything human. A mono for everything keyed.</span>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "18px" }}>
            <div style={{ ...card, padding: "36px" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: "26px" }}>
                <span style={{ fontSize: "22px", fontWeight: 600, letterSpacing: "-0.02em" }}>Schibsted Grotesk</span>
                <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>Display · UI · Body</span>
              </div>
              <div style={{ fontSize: "72px", fontWeight: 700, letterSpacing: "-0.04em", lineHeight: 1 }}>Aa</div>
              <div style={{ fontFamily: mono, fontSize: "12px", color: "var(--faint)", margin: "18px 0 24px", letterSpacing: "0.04em" }}>ABCDEFGHIJKLM · 0123456789 · &amp;?!</div>
              <div style={{ display: "flex", flexDirection: "column", gap: "14px", borderTop: "1px solid var(--bd)", paddingTop: "22px" }}>
                <div style={{ fontSize: "30px", fontWeight: 700, letterSpacing: "-0.03em" }}>Switch. Done.</div>
                <div style={{ fontSize: "18px", fontWeight: 500 }}>The world recedes for a moment.</div>
                <div style={{ fontSize: "15px", color: "var(--dim)", lineHeight: 1.5 }}>Body copy stays quiet and even. Nothing shouts; the hierarchy comes from weight and space, never from color.</div>
              </div>
            </div>
            <div style={{ ...card, padding: "36px" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: "26px" }}>
                <span style={{ fontFamily: mono, fontSize: "20px", fontWeight: 600, letterSpacing: "-0.01em" }}>JetBrains Mono</span>
                <span style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)" }}>Keys · Config · Labels</span>
              </div>
              <div style={{ fontFamily: mono, fontSize: "72px", fontWeight: 500, lineHeight: 1 }}>Aa</div>
              <div style={{ fontFamily: mono, fontSize: "12px", color: "var(--faint)", margin: "18px 0 24px", letterSpacing: "0.04em" }}>abcdefghijklm · 0123456789 · {"{}[]"}</div>
              <div style={{ borderTop: "1px solid var(--bd)", paddingTop: "22px", display: "flex", flexDirection: "column", gap: "16px" }}>
                <div style={{ display: "flex", gap: "8px", alignItems: "center" }}>
                  <kbd style={{ fontFamily: mono, fontSize: "14px", background: "var(--cardhi)", border: "1px solid var(--bdhi)", borderBottomWidth: "2px", borderRadius: "8px", padding: "8px 12px" }}>⌘</kbd>
                  <span style={{ color: "var(--faint)" }}>+</span>
                  <kbd style={{ fontFamily: mono, fontSize: "14px", background: "var(--cardhi)", border: "1px solid var(--bdhi)", borderBottomWidth: "2px", borderRadius: "8px", padding: "8px 14px" }}>Tab</kbd>
                  <span style={{ fontSize: "14px", color: "var(--dim)", marginLeft: "8px" }}>hold to reveal</span>
                </div>
                <pre style={{ fontFamily: mono, fontSize: "13px", color: "var(--dim)", lineHeight: 1.7, margin: 0 }}>
                  <span style={{ color: "var(--faint)" }}># ~/.zentab.toml</span>
                  {"\neveryday  = "}
                  <span style={{ color: "var(--accent)" }}>"cmd+tab"</span>
                  {"\napp_only  = "}
                  <span style={{ color: "var(--accent)" }}>"cmd+`"</span>
                  {"\nglobal    = "}
                  <span style={{ color: "var(--accent)" }}>"opt+tab"</span>
                </pre>
              </div>
            </div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: "14px", marginTop: "14px" }}>
            <div style={{ ...card, borderRadius: "16px", padding: "20px" }}>
              <div style={{ fontSize: "34px", fontWeight: 700, letterSpacing: "-0.03em", lineHeight: 1 }}>Display</div>
              <div style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)", marginTop: "10px" }}>700 · -4% · 1.0</div>
            </div>
            <div style={{ ...card, borderRadius: "16px", padding: "20px" }}>
              <div style={{ fontSize: "22px", fontWeight: 600, letterSpacing: "-0.02em", lineHeight: 1.1 }}>Heading</div>
              <div style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)", marginTop: "10px" }}>600 · -2% · 1.1</div>
            </div>
            <div style={{ ...card, borderRadius: "16px", padding: "20px" }}>
              <div style={{ fontSize: "16px", fontWeight: 500, lineHeight: 1.4 }}>Body text</div>
              <div style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)", marginTop: "10px" }}>500 · 0 · 1.5</div>
            </div>
            <div style={{ ...card, borderRadius: "16px", padding: "20px" }}>
              <div style={{ fontFamily: mono, fontSize: "13px", letterSpacing: "0.14em", color: "var(--dim)", textTransform: "uppercase", lineHeight: 1.4 }}>Label</div>
              <div style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)", marginTop: "10px" }}>mono · +14% · caps</div>
            </div>
          </div>
        </section>

        {/* 04 VOICE */}
        <section id="voice" style={{ position: "relative", zIndex: 2, maxWidth: "1160px", margin: "0 auto", padding: "64px 40px", borderTop: "1px solid var(--bd)" }}>
          <div style={{ display: "flex", alignItems: "baseline", gap: "18px", marginBottom: "48px" }}>
            <span style={sectionLabel}>04</span>
            <h2 style={{ fontSize: "38px", fontWeight: 600, letterSpacing: "-0.03em" }}>Voice</h2>
            <span style={{ fontSize: "16px", color: "var(--faint)", marginLeft: "auto", maxWidth: "320px", textAlign: "right" }}>Terse. Confident. Says less because it's sure.</span>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: "18px", marginBottom: "18px" }}>
            {[
              { n: "01", title: "Opinionated, for you", body: "We make the calls so nothing pulls your attention from the work. Every line decides; the reader never has to." },
              { n: "02", title: "Calm, not loud", body: 'No exclamation marks. No "blazing fast." Speed is shown, never sold.' },
              { n: "03", title: "Plainspoken & warm", body: "Free for everyone, said once like a gift — never as a pitch, never as a comparison." },
            ].map((v) => (
              <div key={v.n} style={{ ...card, padding: "30px" }}>
                <div style={{ fontFamily: mono, fontSize: "12px", color: "var(--accent)", marginBottom: "14px" }}>{v.n}</div>
                <div style={{ fontSize: "21px", fontWeight: 600, letterSpacing: "-0.02em", marginBottom: "10px" }}>{v.title}</div>
                <div style={{ fontSize: "15px", color: "var(--dim)", lineHeight: 1.55 }}>{v.body}</div>
              </div>
            ))}
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "18px" }}>
            <div style={{ ...card, padding: "32px" }}>
              <div style={{ fontFamily: mono, fontSize: "11px", letterSpacing: "0.16em", color: "#5bd6a0", textTransform: "uppercase", marginBottom: "22px" }}>We say</div>
              <div style={{ display: "flex", flexDirection: "column", gap: "18px" }}>
                <div style={{ fontSize: "20px", fontWeight: 500, letterSpacing: "-0.01em" }}>"Window switching that feels instant."</div>
                <div style={{ fontSize: "20px", fontWeight: 500, letterSpacing: "-0.01em" }}>"Fewer choices. Deeper focus."</div>
                <div style={{ fontSize: "20px", fontWeight: 500, letterSpacing: "-0.01em" }}>"Calm, by design."</div>
              </div>
            </div>
            <div style={{ ...card, padding: "32px" }}>
              <div style={{ fontFamily: mono, fontSize: "11px", letterSpacing: "0.16em", color: "#e08a8a", textTransform: "uppercase", marginBottom: "22px" }}>We don't</div>
              <div style={{ display: "flex", flexDirection: "column", gap: "18px" }}>
                {['"Blazing-fast, hyper-customizable!!!"', '"The switcher that beats the rest."', '"Sign up now — limited time."'].map((t) => (
                  <div key={t} style={{ fontSize: "20px", fontWeight: 500, letterSpacing: "-0.01em", color: "var(--faint)", textDecoration: "line-through", textDecorationColor: "rgba(224,138,138,0.5)" }}>{t}</div>
                ))}
              </div>
            </div>
          </div>
        </section>

        {/* 05 BRAND IN USE */}
        <section id="overlay" style={{ position: "relative", zIndex: 2, maxWidth: "1160px", margin: "0 auto", padding: "64px 40px", borderTop: "1px solid var(--bd)" }}>
          <div style={{ display: "flex", alignItems: "baseline", gap: "18px", marginBottom: "14px" }}>
            <span style={sectionLabel}>05</span>
            <h2 style={{ fontSize: "38px", fontWeight: 600, letterSpacing: "-0.03em" }}>In use — the overlay</h2>
            <span style={{ fontSize: "16px", color: "var(--faint)", marginLeft: "auto", maxWidth: "330px", textAlign: "right" }}>Where the brand actually lives: a thumbnail of every window, the focus quietly lit.</span>
          </div>

          <div style={{ background: "linear-gradient(160deg,#15171f,#0d0e13)", border: "1px solid var(--bd)", borderRadius: "24px", padding: "54px 40px 46px", position: "relative", overflow: "hidden" }}>
            <div style={{ position: "absolute", inset: 0, backgroundImage: "linear-gradient(var(--bd) 1px,transparent 1px),linear-gradient(90deg,var(--bd) 1px,transparent 1px)", backgroundSize: "40px 40px", opacity: 0.22 }} />
            <div style={{ position: "absolute", top: "-120px", left: "50%", transform: "translateX(-50%)", width: "520px", height: "300px", background: "radial-gradient(circle,rgba(93,109,255,0.16),transparent 70%)", filter: "blur(10px)" }} />
            <div style={{ position: "relative", display: "flex", flexDirection: "column", alignItems: "center", gap: "26px" }}>
              <div style={{ display: "flex", gap: "16px", padding: "16px", background: "rgba(28,30,38,0.72)", backdropFilter: "blur(20px)", border: "1px solid rgba(255,255,255,0.1)", borderRadius: "22px", boxShadow: "0 30px 80px rgba(0,0,0,0.5)", maxWidth: "760px", width: "100%" }}>
                {wins.map((win, i) => {
                  const on = i === active;
                  return (
                    <div key={win.title} onMouseEnter={() => this.setState({ active: i })} style={{ flex: 1, cursor: "pointer", borderRadius: "14px", padding: "5px", border: on ? "2px solid #5d6dff" : "2px solid transparent", background: on ? "rgba(93,109,255,0.10)" : "rgba(255,255,255,0.02)", boxShadow: on ? "0 10px 30px rgba(93,109,255,0.28)" : "none", transition: "all .3s cubic-bezier(.22,.61,.36,1)" }}>
                      <div style={{ position: "relative", width: "100%", paddingTop: "62%", borderRadius: "9px", overflow: "hidden", border: "1px solid rgba(255,255,255,0.06)" }}>{thumbInner(win.type)}</div>
                      <div style={{ display: "flex", alignItems: "center", gap: "8px", padding: "9px 5px 4px" }}>
                        <div style={{ width: "18px", height: "18px", borderRadius: "5px", flex: "none", background: win.icon, display: "flex", alignItems: "center", justifyContent: "center", fontSize: "10px", color: "#fff", fontWeight: 700 }}>{win.letter}</div>
                        <span style={{ fontSize: "13px", fontWeight: on ? 600 : 500, color: on ? "#ECEDF1" : "#9b9ea9", letterSpacing: "-0.01em", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", transition: "color .3s ease" }}>{win.title}</span>
                      </div>
                    </div>
                  );
                })}
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                <kbd style={{ fontFamily: mono, fontSize: "13px", background: "var(--cardhi)", border: "1px solid var(--bdhi)", borderBottomWidth: "2px", borderRadius: "7px", padding: "6px 10px" }}>⌘</kbd>
                <kbd style={{ fontFamily: mono, fontSize: "13px", background: "var(--cardhi)", border: "1px solid var(--bdhi)", borderBottomWidth: "2px", borderRadius: "7px", padding: "6px 12px" }}>Tab</kbd>
                <span style={{ fontSize: "14px", color: "var(--faint)", marginLeft: "6px" }}>held — Tab to move, release commits</span>
              </div>
            </div>
          </div>

          <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: "18px", marginTop: "18px" }}>
            {[
              { title: "Stable order", body: "Tiles never reshuffle by recency. Slack is always 4th — so your hand already knows." },
              { title: "One ring", body: "A single accent ring marks focus. Everything else is held in calm grayscale." },
              { title: "Two actions", body: "W closes a window, Q quits an app. Anything more is the OS's job, not ours." },
            ].map((p) => (
              <div key={p.title} style={{ ...card, borderRadius: "18px", padding: "24px" }}>
                <div style={{ fontFamily: mono, fontSize: "11px", letterSpacing: "0.14em", color: "var(--faint)", textTransform: "uppercase", marginBottom: "10px" }}>{p.title}</div>
                <div style={{ fontSize: "15px", color: "var(--dim)", lineHeight: 1.5 }}>{p.body}</div>
              </div>
            ))}
          </div>
        </section>

        {/* FOOTER */}
        <section style={{ position: "relative", zIndex: 2, maxWidth: "1160px", margin: "0 auto", padding: "70px 40px 90px", borderTop: "1px solid var(--bd)", display: "flex", justifyContent: "space-between", alignItems: "flex-end", flexWrap: "wrap", gap: "24px" }}>
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "14px" }}>
              <div style={{ position: "relative", width: "30px", height: "30px" }}>
                <div style={{ position: "absolute", inset: 0, border: "1.6px solid var(--bdhi)", borderRadius: "8px" }} />
                <div style={{ position: "absolute", left: "9px", top: "9px", width: "21px", height: "21px", background: "linear-gradient(145deg,#7282ff,#5160ff)", borderRadius: "7px" }} />
              </div>
              <span style={{ fontWeight: 600, fontSize: "19px", letterSpacing: "-0.02em" }}>ZenTab</span>
            </div>
            <div style={{ fontSize: "15px", color: "var(--faint)", maxWidth: "340px", lineHeight: 1.5 }}>The switcher is a moment where the rest of the world recedes.</div>
          </div>
          <div style={{ fontFamily: mono, fontSize: "11px", color: "var(--faint)", letterSpacing: "0.1em", textAlign: "right", lineHeight: 1.8 }}>
            <div><Link to="/" className="zt-link">Home</Link> · <Link to="/overlay" className="zt-link">Overlay</Link></div>
            <div>macOS · Windows</div>
            <div>FREE FOREVER</div>
          </div>
        </section>
      </div>
    );
  }
}
