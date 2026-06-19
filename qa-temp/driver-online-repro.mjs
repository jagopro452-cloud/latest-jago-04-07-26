import fs from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";

const appRoot = "C:/Users/kiran/Downloads/jago_version_2026-Update-02-06-26-jago/jago_version_2026-Update-02-06-26-jago/canonical-app";
const require = createRequire(path.join(appRoot, "package.json"));
const { io } = require("socket.io-client");
const statePath = path.join(appRoot, "test-results", ".live", "suite-state.json");
const raw = await fs.readFile(statePath, "utf8");
const state = JSON.parse(raw);
const session = state?.actors?.driverBikePrimary?.session;

if (!session?.token || !session?.user?.id) {
  throw new Error("Missing driverBikePrimary session in live suite state.");
}

const socket = io("http://localhost:5002", {
  transports: ["websocket", "polling"],
  path: "/socket.io",
  query: {
    userId: session.user.id,
    userType: "driver",
    token: session.token,
  },
  auth: {
    token: session.token,
  },
  forceNew: true,
  reconnection: false,
  timeout: 20_000,
});

socket.on("connect", async () => {
  console.log("CONNECT", socket.id);
  socket.onAny((event, payload) => {
    console.log("EVENT", event, JSON.stringify(payload ?? null));
  });
  await new Promise((resolve) => setTimeout(resolve, 500));
  console.log("EMIT driver:online");
  socket.emit("driver:online", {
    isOnline: true,
    lat: 17.385,
    lng: 78.4867,
  });
});

socket.on("connect_error", (error) => {
  console.error("CONNECT_ERROR", error?.message || error);
  process.exit(1);
});

socket.on("auth:error", (payload) => {
  console.error("AUTH_ERROR", JSON.stringify(payload ?? null));
});

setTimeout(() => {
  console.log("TIMEOUT");
  socket.close();
  process.exit(0);
}, 8_000);
