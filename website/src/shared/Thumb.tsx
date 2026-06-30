import type { ReactNode } from "react";

// A window's "kind", which decides the little faux-app thumbnail we draw.
export type ThumbType =
  | "editor"
  | "darkui"
  | "chat"
  | "terminal"
  | "mail"
  | "browser";

// One window in a switcher scope.
export interface WindowItem {
  app: string;
  title: string;
  color: string;
  letter: string;
  type: ThumbType;
  badge?: string | null;
  here?: boolean;
}

// A single bar of "content" inside a thumbnail. Children passed as separate
// JSX expressions, so no keys are required.
function bar(w: string, c?: string, o?: number): ReactNode {
  return (
    <div
      style={{
        height: "3px",
        borderRadius: "2px",
        width: w,
        background: c ?? "rgba(255,255,255,0.4)",
        opacity: o ?? 1,
      }}
    />
  );
}

// The faux-application thumbnail. Mirrors the design's `thumb(type)` helper.
export function Thumb({ type }: { type: ThumbType }) {
  if (type === "editor") {
    return (
      <div style={{ position: "absolute", inset: 0, background: "#14151b", display: "flex" }}>
        <div
          style={{
            width: "28%",
            padding: "10px 7px",
            display: "flex",
            flexDirection: "column",
            gap: "6px",
            borderRight: "1px solid rgba(255,255,255,0.05)",
          }}
        >
          {bar("70%", "rgba(255,255,255,0.3)")}
          {bar("85%", "rgba(255,255,255,0.16)")}
          {bar("55%")}
          {bar("78%", "rgba(255,255,255,0.16)")}
          {bar("62%", "rgba(255,255,255,0.16)")}
        </div>
        <div style={{ flex: 1, padding: "10px", display: "flex", flexDirection: "column", gap: "6px" }}>
          {bar("40%", "#5d6dff", 0.9)}
          {bar("88%", "rgba(255,255,255,0.16)")}
          {bar("70%", "rgba(255,255,255,0.16)")}
          {bar("50%", "#5bd6a0", 0.7)}
          {bar("80%", "rgba(255,255,255,0.16)")}
          {bar("34%", "#e0a05b", 0.7)}
        </div>
      </div>
    );
  }
  if (type === "darkui") {
    return (
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: "#0c0d12",
          display: "flex",
          flexDirection: "column",
          gap: "9px",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <div
          style={{
            width: "60%",
            height: "30%",
            borderRadius: "7px",
            background: "rgba(255,255,255,0.04)",
            border: "1px solid rgba(93,109,255,0.4)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <div
            style={{
              width: "28px",
              height: "11px",
              borderRadius: "4px",
              background: "linear-gradient(145deg,#7282ff,#5160ff)",
            }}
          />
        </div>
        <div style={{ display: "flex", gap: "6px" }}>
          {bar("32px", "rgba(255,255,255,0.12)")}
          {bar("20px", "rgba(255,255,255,0.12)")}
        </div>
      </div>
    );
  }
  if (type === "chat") {
    return (
      <div style={{ position: "absolute", inset: 0, background: "#16181d", display: "flex" }}>
        <div
          style={{
            width: "26%",
            background: "rgba(91,214,160,0.08)",
            padding: "9px 6px",
            display: "flex",
            flexDirection: "column",
            gap: "6px",
          }}
        >
          {bar("80%", "rgba(91,214,160,0.5)")}
          {bar("60%")}
          {bar("70%")}
        </div>
        <div style={{ flex: 1, padding: "10px", display: "flex", flexDirection: "column", gap: "7px" }}>
          {bar("75%", "rgba(255,255,255,0.16)")}
          {bar("55%", "rgba(255,255,255,0.16)")}
          {bar("85%", "rgba(255,255,255,0.16)")}
        </div>
      </div>
    );
  }
  if (type === "terminal") {
    return (
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: "#0a0b0e",
          padding: "10px",
          display: "flex",
          flexDirection: "column",
          gap: "6px",
          fontFamily: "monospace",
        }}
      >
        {bar("46%", "#5bd6a0", 0.8)}
        {bar("70%", "rgba(255,255,255,0.22)")}
        {bar("60%", "rgba(255,255,255,0.22)")}
        {bar("30%", "#5bd6a0", 0.8)}
        {bar("50%", "rgba(255,255,255,0.22)")}
      </div>
    );
  }
  if (type === "mail") {
    return (
      <div style={{ position: "absolute", inset: 0, background: "#101218", display: "flex" }}>
        <div
          style={{
            width: "36%",
            borderRight: "1px solid rgba(255,255,255,0.06)",
            padding: "9px 7px",
            display: "flex",
            flexDirection: "column",
            gap: "7px",
          }}
        >
          {bar("80%", "rgba(93,109,255,0.5)")}
          {bar("60%")}
          {bar("70%")}
          {bar("55%")}
        </div>
        <div style={{ flex: 1, padding: "10px", display: "flex", flexDirection: "column", gap: "6px" }}>
          {bar("70%", "rgba(255,255,255,0.2)")}
          {bar("90%", "rgba(255,255,255,0.14)")}
          {bar("80%", "rgba(255,255,255,0.14)")}
        </div>
      </div>
    );
  }
  // browser (light)
  return (
    <div style={{ position: "absolute", inset: 0, background: "#f4f2ec" }}>
      <div
        style={{
          height: "20%",
          background: "#e7e3d8",
          display: "flex",
          alignItems: "center",
          gap: "4px",
          padding: "0 8px",
        }}
      >
        <div style={{ width: "5px", height: "5px", borderRadius: "50%", background: "#c8c2b2" }} />
        <div style={{ width: "5px", height: "5px", borderRadius: "50%", background: "#c8c2b2" }} />
      </div>
      <div style={{ display: "flex", padding: "11px 12px", gap: "12px" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "6px" }}>
          {bar("80%", "#33312b")}
          {bar("90%", "rgba(0,0,0,0.18)")}
          {bar("65%", "rgba(0,0,0,0.18)")}
        </div>
        <div style={{ width: "36%", height: "40px", borderRadius: "6px", background: "#1c1b18" }} />
      </div>
    </div>
  );
}
