import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, it } from "node:test";

import { loadConfig } from "./config.js";
import { transcribeFile } from "./transcribe.js";

const originalFetch = globalThis.fetch;

type MockFetch = (typeof globalThis)["fetch"];

afterEach(() => {
  globalThis.fetch = originalFetch;
});

describe("transcribeFile retry behavior", () => {
  it("retries once when backend returns empty transcript", async () => {
    const { dirPath, filePath } = await createTempAudioFile();
    const config = createTestConfig();
    let calls = 0;

    globalThis.fetch = (async () => {
      calls += 1;
      if (calls === 1) {
        return createCompletionResponse("language None<asr_text>");
      }

      return createCompletionResponse("hello world");
    }) as MockFetch;

    try {
      const text = await transcribeFile(filePath, config);
      assert.equal(text, "hello world");
      assert.equal(calls, 2);
    } finally {
      await rm(dirPath, { recursive: true, force: true });
    }
  });

  it("retries once when request times out", async () => {
    const { dirPath, filePath } = await createTempAudioFile();
    const config = createTestConfig();
    let calls = 0;

    globalThis.fetch = (async () => {
      calls += 1;
      if (calls === 1) {
        const abortError = new Error("request aborted");
        abortError.name = "AbortError";
        throw abortError;
      }

      return createCompletionResponse("retry success");
    }) as MockFetch;

    try {
      const text = await transcribeFile(filePath, config);
      assert.equal(text, "retry success");
      assert.equal(calls, 2);
    } finally {
      await rm(dirPath, { recursive: true, force: true });
    }
  });

  it("does not retry backend 5xx errors", async () => {
    const { dirPath, filePath } = await createTempAudioFile();
    const config = createTestConfig();
    let calls = 0;

    globalThis.fetch = (async () => {
      calls += 1;
      return new Response("unavailable", { status: 503 });
    }) as MockFetch;

    try {
      await assert.rejects(() => transcribeFile(filePath, config), /Backend returned 503/);
      assert.equal(calls, 1);
    } finally {
      await rm(dirPath, { recursive: true, force: true });
    }
  });
});

function createTestConfig() {
  return loadConfig({
    ...process.env,
    VOICE_ENDPOINT: "http://127.0.0.1:18000/v1/chat/completions",
    VOICE_MODEL: "qwen3-asr",
    VOICE_REQUEST_TIMEOUT_MS: "50"
  });
}

async function createTempAudioFile(): Promise<{ dirPath: string; filePath: string }> {
  const dirPath = await mkdtemp(join(tmpdir(), "omaboard-transcribe-test-"));
  const filePath = join(dirPath, "sample.wav");
  await writeFile(filePath, Buffer.from([82, 73, 70, 70]));
  return { dirPath, filePath };
}

function createCompletionResponse(content: string): Response {
  return new Response(
    JSON.stringify({
      choices: [
        {
          message: {
            content
          }
        }
      ]
    }),
    {
      status: 200,
      headers: {
        "Content-Type": "application/json"
      }
    }
  );
}
