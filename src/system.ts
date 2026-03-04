import { spawn } from "node:child_process";

export async function copyToClipboard(command: string, text: string): Promise<void> {
  await runCommand(command, [], text);
}

export async function sendNotification(
  command: string,
  title: string,
  body: string
): Promise<void> {
  await runCommand(command, [title, body]);
}

async function runCommand(command: string, args: string[], input?: string): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: ["pipe", "ignore", "pipe"]
    });

    let stderr = "";

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    child.once("error", (error) => {
      reject(new Error(`Failed to start ${command}: ${error.message}`));
    });

    child.once("close", (code) => {
      if (code === 0) {
        resolve();
        return;
      }

      const extra = stderr.trim().length > 0 ? `: ${stderr.trim()}` : "";
      reject(new Error(`${command} exited with code ${String(code)}${extra}`));
    });

    if (input !== undefined) {
      child.stdin.write(input);
    }

    child.stdin.end();
  });
}
