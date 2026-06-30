import { Routes, Route } from "react-router-dom";
import Landing from "./pages/Landing.tsx";
import Overlay from "./pages/Overlay.tsx";
import Brand from "./pages/Brand.tsx";

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Landing />} />
      <Route path="/overlay" element={<Overlay />} />
      <Route path="/brand" element={<Brand />} />
    </Routes>
  );
}
