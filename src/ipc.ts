import net from "node:net";

import type { VoiceState } from "./state-machine.js";

export type VoiceAction = "start" | "stop" | "status";

export interface VoiceRequest {
  action: VoiceAction;
}

export interface VoiceResponse {
  ok: boolean;
  message: string;
  state: VoiceState;
  text?: string;
  error?: string;
}

export async function sendIpcRequest(
  socketPath: string,
  request: VoiceRequest
): Promise<VoiceResponse> {
  return new Promise((resolve, reject) => {
    const client = net.createConnection(socketPath);
    let responseBuffer = "";

    client.on("connect", () => {
      client.write(`${JSON.stringify(request)}\n`);
    });

    client.on("data", (chunk) => {
      responseBuffer += chunk.toString();
      const newlineIndex = responseBuffer.indexOf("\n");

      if (newlineIndex < 0) {
        return;
      }

      const line = responseBuffer.slice(0, newlineIndex).trim();

      try {
        const response = JSON.parse(line) as VoiceResponse;
        resolve(response);
      } catch (error) {
        reject(
          new Error(
            `Failed to parse daemon response: ${error instanceof Error ? error.message : String(error)}`
          )
        );
      } finally {
        client.end();
      }
    });

    client.on("error", (error) => {
      reject(new Error(`Failed to reach daemon on ${socketPath}: ${error.message}`));
    });

    client.on("end", () => {
      if (responseBuffer.trim().length === 0) {
        reject(new Error("Daemon closed connection without response"));
      }
    });
  });
}
