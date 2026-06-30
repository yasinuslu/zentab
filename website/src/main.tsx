import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import App from "./App.tsx";
import "./theme.css";

const root = document.getElementById("root");
if (!root) throw new Error("missing #root element");

// Vite's base ("/" in dev, "/zentab/" on GitHub Pages) drives the router base
// so cross-route <Link>s resolve correctly under the project subpath.
const basename = import.meta.env.BASE_URL.replace(/\/$/, "");

createRoot(root).render(
  <StrictMode>
    <BrowserRouter basename={basename}>
      <App />
    </BrowserRouter>
  </StrictMode>,
);
