import { readFile } from "node:fs/promises";
import { basename } from "node:path";

import type { AppConfig } from "./config.js";

export async function transcribeFile(filePath: string, config: AppConfig): Promise<string> {
  const audioData = await readFile(filePath);

  const form = new FormData();
  form.append(
    config.audioField,
    new Blob([audioData], {
      type: "audio/wav"
    }),
    basename(filePath)
  );

  if (config.model) {
    form.append("model", config.model);
  }

  if (config.language) {
    form.append("language", config.language);
  }

  const abortController = new AbortController();
  const timeout = setTimeout(() => {
    abortController.abort();
  }, config.requestTimeoutMs);

  try {
    const response = await fetch(config.endpoint, {
      method: "POST",
      headers: buildHeaders(config),
      body: form,
      signal: abortController.signal
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`Backend returned ${response.status}: ${truncate(body, 400)}`);
    }

    const contentType = response.headers.get("content-type") ?? "";

    if (contentType.includes("application/json")) {
      const payload: unknown = await response.json();
      const text = extractText(payload, config.textField);

      if (!text) {
        throw new Error(`JSON response is missing string field "${config.textField}"`);
      }

      return text;
    }

    const plainText = (await response.text()).trim();
    if (!plainText) {
      throw new Error("Backend response body is empty");
    }

    return plainText;
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new Error(`Transcription timed out after ${config.requestTimeoutMs}ms`);
    }

    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

function buildHeaders(config: AppConfig): HeadersInit {
  if (!config.apiKey) {
    return {};
  }

  return {
    Authorization: `Bearer ${config.apiKey}`
  };
}

function extractText(payload: unknown, path: string): string | null {
  const segments = path.split(".").filter((segment) => segment.length > 0);
  let current: unknown = payload;

  for (const segment of segments) {
    if (Array.isArray(current)) {
      const index = Number.parseInt(segment, 10);
      if (!Number.isInteger(index)) {
        return null;
      }

      current = current[index];
      continue;
    }

    if (typeof current === "object" && current !== null) {
      current = (current as Record<string, unknown>)[segment];
      continue;
    }

    return null;
  }

  if (typeof current !== "string") {
    return null;
  }

  const trimmed = current.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function truncate(text: string, maxLength: number): string {
  if (text.length <= maxLength) {
    return text;
  }

  return `${text.slice(0, maxLength)}...`;
}
