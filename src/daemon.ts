#!/usr/bin/env node

import net from "node:net";
import { mkdir, rm } from "node:fs/promises";
import { dirname } from "node:path";

import { loadConfig } from "./config.js";
import type { VoiceAction, VoiceRequest, VoiceResponse } from "./ipc.js";
import { VoiceService } from "./service.js";

async function main(): Promise<void> {
  const config = loadConfig();
  const service = new VoiceService(config);
  const server = net.createServer();

  await mkdir(dirname(config.socketPath), { recursive: true });
  await rm(config.socketPath, { force: true });

  server.on("connection", (socket) => {
    let buffer = "";

    socket.on("data", (chunk) => {
      buffer += chunk.toString();
      const newlineIndex = buffer.indexOf("\n");

      if (newlineIndex < 0) {
        return;
      }

      const raw = buffer.slice(0, newlineIndex).trim();
      buffer = "";

      void handleRequest(raw, service)
        .then((response) => {
          socket.end(`${JSON.stringify(response)}\n`);
        })
        .catch((error: unknown) => {
          const message = error instanceof Error ? error.message : String(error);
          const fallback: VoiceResponse = {
            ok: false,
            message,
            state: "idle",
            error: message
          };
          socket.end(`${JSON.stringify(fallback)}\n`);
        });
    });
  });

  server.listen(config.socketPath, () => {
    console.log(`voice-daemon listening on ${config.socketPath}`);
  });

  const shutdown = async (signal: NodeJS.Signals): Promise<void> => {
    console.log(`voice-daemon received ${signal}, shutting down`);

    server.close();
    await service.shutdown();
    await rm(config.socketPath, { force: true });

    process.exit(0);
  };

  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.on(signal, () => {
      void shutdown(signal);
    });
  }
}

async function handleRequest(raw: string, service: VoiceService): Promise<VoiceResponse> {
  let request: VoiceRequest;

  try {
    request = JSON.parse(raw) as VoiceRequest;
  } catch {
    return {
      ok: false,
      message: "Invalid JSON request",
      state: "idle",
      error: "Invalid JSON request"
    };
  }

  if (!isVoiceAction(request.action)) {
    return {
      ok: false,
      message: `Invalid action: ${String(request.action)}`,
      state: "idle",
      error: "Invalid action"
    };
  }

  return service.handleAction(request.action);
}

function isVoiceAction(value: unknown): value is VoiceAction {
  return value === "start" || value === "stop" || value === "status";
}

void main().catch((error) => {
  console.error(error);
  process.exit(1);
});
