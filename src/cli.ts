#!/usr/bin/env node

import { loadConfig } from "./config.js";
import { sendIpcRequest, type VoiceAction } from "./ipc.js";

async function main(): Promise<void> {
  const action = parseAction(process.argv[2]);

  if (!action) {
    printUsage();
    process.exit(1);
  }

  const config = loadConfig();

  try {
    const response = await sendIpcRequest(config.socketPath, { action });

    if (response.ok) {
      if (action === "stop" && response.text) {
        console.log(response.text);
      } else {
        console.log(response.message);
      }
      process.exit(0);
      return;
    }

    console.error(response.error ?? response.message);
    process.exit(1);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message);
    process.exit(1);
  }
}

function parseAction(raw: string | undefined): VoiceAction | null {
  if (raw === "start" || raw === "stop" || raw === "status") {
    return raw;
  }

  return null;
}

function printUsage(): void {
  console.error("Usage: voicectl <start|stop|status>");
}

void main();
