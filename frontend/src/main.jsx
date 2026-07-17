/**
 * main.jsx — React application entry point.
 *
 * LAYMAN: This is the "power switch" for the React app.
 * It mounts the entire app into the HTML page (index.html has a <div id="root">)
 * and wraps everything in StrictMode which helps catch bugs during development.
 */

import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
