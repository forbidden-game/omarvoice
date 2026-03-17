import { execFileSync, spawn, type ChildProcess } from "node:child_process";
import { readFile, rm, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

import type { AppConfig } from "./config.js";

const HEALTH_CHECK_INTERVAL_MS = 300;
const HEALTH_CHECK_TIMEOUT_MS = 30_000;
const SHUTDOWN_GRACE_MS = 3_000;

/**
 * Manages the lifecycle of the local SenseVoice Python backend.
 *
 * In "managed" mode, the daemon owns the backend process:
 *   - Starts it as a new process group (detached)
 *   - Writes a PID file for crash-path cleanup
 *   - Health-checks via GET /health before declaring readiness
 *   - Kills the entire process group on shutdown
 *
 * In "external" mode, this class is a no-op.
 */
export class BackendManager {
  private child: ChildProcess | null = null;
  private readonly managed: boolean;
  private readonly pidFile: string;
  private readonly script: string;
  private readonly healthUrl: string;
  private readonly backendHost: string;
  private readonly backendPort: string;

  public constructor(private readonly config: AppConfig) {
    this.managed = config.backendMode === "managed";
    this.pidFile = config.backendPidFile;
    this.script = config.backendScript;

    // Parse host/port from endpoint so managed backend and health check stay in sync.
    // endpoint is e.g. http://127.0.0.1:8000/v1/chat/completions
    const endpointUrl = new URL(config.endpoint);
    this.backendHost = endpointUrl.hostname;
    this.backendPort = endpointUrl.port || "8000";
    this.healthUrl = `${endpointUrl.protocol}//${endpointUrl.host}/health`;
  }

  /**
   * Start the backend if in managed mode.
   * Cleans up any stale process from a previous crash first.
   */
  public async start(): Promise<void> {
    if (!this.managed) {
      return;
    }

    // Crash-path cleanup: if a previous daemon died without cleaning up,
    // a stale Python process may still hold the port.
    await this.killStalePid();

    // If something else is already healthy on the port, skip spawning.
    if (await this.isHealthy()) {
      console.log("backend-manager: backend already healthy, skipping spawn");
      return;
    }

    await this.spawnBackend();
    await this.waitForHealth();
  }

  /** Stop the backend if we spawned it. */
  public async stop(): Promise<void> {
    if (!this.managed) {
      return;
    }

    await this.killChild();
    await this.removePidFile();
  }

  // -----------------------------------------------------------------------
  // Internal
  // -----------------------------------------------------------------------

  private async spawnBackend(): Promise<void> {
    const venvPython = `${dirname(this.script)}/.venv/bin/python3`;

    // Prefer repo-local venv; fall back to system python3.
    const pythonBin = (await fileExists(venvPython)) ? venvPython : "python3";

    const child = spawn(
      pythonBin,
      [this.script, "--host", this.backendHost, "--port", this.backendPort],
      {
        detached: true,
        stdio: ["ignore", "pipe", "pipe"],
        cwd: dirname(this.script)
      }
    );

    child.unref();
    this.child = child;

    // Forward backend output to daemon's stderr for debugging.
    child.stdout?.on("data", (chunk: Buffer) => {
      process.stderr.write(`[backend] ${chunk.toString()}`);
    });
    child.stderr?.on("data", (chunk: Buffer) => {
      process.stderr.write(`[backend] ${chunk.toString()}`);
    });

    child.on("exit", (code, signal) => {
      console.log(`backend-manager: backend exited (code=${code}, signal=${signal})`);
      this.child = null;
    });

    // Write PID file so crash-path cleanup can find the process.
    if (child.pid !== undefined) {
      await writeFile(this.pidFile, String(child.pid), "utf-8");
      console.log(`backend-manager: started backend pid=${child.pid}`);
    }
  }

  private async waitForHealth(): Promise<void> {
    const deadline = Date.now() + HEALTH_CHECK_TIMEOUT_MS;

    while (Date.now() < deadline) {
      if (await this.isHealthy()) {
        console.log("backend-manager: backend is healthy");
        return;
      }

      // If the child already exited, no point waiting.
      if (this.child === null) {
        throw new Error("backend-manager: backend exited before becoming healthy");
      }

      await sleep(HEALTH_CHECK_INTERVAL_MS);
    }

    throw new Error(
      `backend-manager: backend did not become healthy within ${HEALTH_CHECK_TIMEOUT_MS}ms`
    );
  }

  private async isHealthy(): Promise<boolean> {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 2_000);

      const response = await fetch(this.healthUrl, { signal: controller.signal });
      clearTimeout(timeout);
      return response.ok;
    } catch {
      return false;
    }
  }

  /** Kill the child process group. */
  private async killChild(): Promise<void> {
    if (!this.child || this.child.exitCode !== null) {
      this.child = null;
      return;
    }

    const pid = this.child.pid;
    if (pid === undefined) {
      return;
    }

    // Kill the entire process group (negative PID).
    try {
      process.kill(-pid, "SIGTERM");
    } catch {
      // Process may already be gone.
    }

    // Wait for exit, escalate to SIGKILL if needed.
    const exited = await this.waitForExit(this.child, SHUTDOWN_GRACE_MS);
    if (!exited) {
      try {
        process.kill(-pid, "SIGKILL");
      } catch {
        // Already gone.
      }
    }

    this.child = null;
  }

  /** Kill a stale backend from a previous crash using the PID file. */
  private async killStalePid(): Promise<void> {
    let raw: string;
    try {
      raw = await readFile(this.pidFile, "utf-8");
    } catch {
      return; // No PID file — nothing to clean up.
    }

    const pid = Number.parseInt(raw.trim(), 10);
    if (!Number.isFinite(pid) || pid <= 0) {
      await this.removePidFile();
      return;
    }

    // Check if the process is still alive.
    try {
      process.kill(pid, 0);
    } catch {
      // Process is gone — just clean up the PID file.
      await this.removePidFile();
      return;
    }

    // Verify this PID is actually our backend process, not an unrelated process
    // that reused the same PID number after a crash.  Match the full script path.
    if (!isOwnedProcess(pid, this.script)) {
      console.log(`backend-manager: stale pid=${pid} is not a backend process, skipping kill`);
      await this.removePidFile();
      return;
    }

    console.log(`backend-manager: killing stale backend pid=${pid}`);
    try {
      process.kill(-pid, "SIGTERM");
    } catch {
      // Try without process group (might not be a group leader).
      try {
        process.kill(pid, "SIGTERM");
      } catch {
        // Already gone.
      }
    }

    // Give it a moment, then SIGKILL if needed.
    await sleep(1_000);
    try {
      process.kill(pid, 0);
      // Still alive — force kill.
      try {
        process.kill(-pid, "SIGKILL");
      } catch {
        try {
          process.kill(pid, "SIGKILL");
        } catch {
          // Give up.
        }
      }
    } catch {
      // Gone.
    }

    await this.removePidFile();
  }

  private async removePidFile(): Promise<void> {
    await rm(this.pidFile, { force: true });
  }

  private waitForExit(child: ChildProcess, timeoutMs: number): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      if (child.exitCode !== null || child.signalCode !== null) {
        resolve(true);
        return;
      }

      const timeout = setTimeout(() => {
        child.removeListener("exit", onExit);
        resolve(false);
      }, timeoutMs);

      const onExit = (): void => {
        clearTimeout(timeout);
        resolve(true);
      };

      child.once("exit", onExit);
    });
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Check if a PID belongs to a process whose command line contains the given
 * script path.  Uses the full absolute path so we won't match an unrelated
 * process that happens to run a different file with the same basename.
 */
function isOwnedProcess(pid: number, scriptPath: string): boolean {
  try {
    const output = execFileSync("ps", ["-p", String(pid), "-o", "command="], {
      encoding: "utf-8",
      timeout: 3_000
    }).trim();
    return output.includes(scriptPath);
  } catch {
    return false;
  }
}

async function fileExists(path: string): Promise<boolean> {
  try {
    const { access } = await import("node:fs/promises");
    await access(path);
    return true;
  } catch {
    return false;
  }
}
