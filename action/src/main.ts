import * as core from "@actions/core";
import * as exec from "@actions/exec";
import * as github from "@actions/github";
import * as io from "@actions/io";
import * as crypto from "crypto";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

import { upsertStickyComment, STICKY_MARKER } from "./comment";

interface Inputs {
  githubToken: string;
  workingDirectory: string;
  comment: boolean;
  failOnRegression: boolean;
  installElan: boolean;
  oracleJarUrl: string;
  oracleSha256: string;
}

function getInputs(): Inputs {
  return {
    githubToken: core.getInput("github-token"),
    workingDirectory: core.getInput("working-directory") || ".",
    comment: core.getBooleanInput("comment"),
    failOnRegression: core.getBooleanInput("fail-on-regression"),
    installElan: core.getBooleanInput("install-elan"),
    oracleJarUrl: core.getInput("oracle-jar-url"),
    oracleSha256: core.getInput("oracle-sha256"),
  };
}

/** Run a command and capture stdout, optionally tolerating nonzero exit. */
async function execCapture(
  command: string,
  args: string[],
  options: exec.ExecOptions = {}
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  let stdout = "";
  let stderr = "";
  const exitCode = await exec.exec(command, args, {
    ...options,
    ignoreReturnCode: true,
    listeners: {
      stdout: (data: Buffer) => {
        stdout += data.toString();
      },
      stderr: (data: Buffer) => {
        stderr += data.toString();
      },
    },
  });
  return { stdout, stderr, exitCode };
}

async function commandExists(command: string): Promise<boolean> {
  try {
    await io.which(command, true);
    return true;
  } catch {
    return false;
  }
}

/** Ensure `lake` (and thus the Lean toolchain) is available on PATH. */
async function ensureLean(inputs: Inputs): Promise<void> {
  if (await commandExists("lake")) {
    core.info("lake already on PATH; skipping elan install.");
    return;
  }

  if (!inputs.installElan) {
    core.warning(
      "lake not found on PATH and install-elan is false; subsequent steps will likely fail."
    );
    return;
  }

  core.info("Installing elan (Lean toolchain manager)...");
  const script = await execCapture("curl", [
    "-sSfL",
    "https://elan.lean-lang.org/elan-init.sh",
  ]);
  if (script.exitCode !== 0 || !script.stdout) {
    throw new Error("failed to download elan-init.sh");
  }

  const scriptPath = path.join(os.tmpdir(), "elan-init.sh");
  fs.writeFileSync(scriptPath, script.stdout, { mode: 0o755 });

  const install = await exec.exec("sh", [
    scriptPath,
    "-y",
    "--default-toolchain",
    "none",
  ]);
  if (install !== 0) {
    throw new Error("elan-init.sh failed");
  }

  const elanBin = path.join(os.homedir(), ".elan", "bin");
  core.addPath(elanBin);
  core.info(`Added ${elanBin} to PATH.`);
}

/** Best-effort fetch of the second-source oracle jar. Never fatal. */
async function maybeFetchOracle(inputs: Inputs): Promise<void> {
  if (!inputs.oracleJarUrl) {
    return;
  }

  try {
    await io.mkdirP("vendor");
    const jarPath = path.join("vendor", "MCSysMLv2.jar");
    const result = await exec.exec(
      "curl",
      ["-sSfL", "-o", jarPath, inputs.oracleJarUrl],
      { ignoreReturnCode: true }
    );

    if (result !== 0) {
      core.warning(
        "could not fetch oracle jar; oracle round-trip will be skipped"
      );
      return;
    }

    if (inputs.oracleSha256) {
      const digest = crypto
        .createHash("sha256")
        .update(fs.readFileSync(jarPath))
        .digest("hex");
      if (digest.toLowerCase() !== inputs.oracleSha256.toLowerCase()) {
        core.warning(
          "oracle jar checksum mismatch (upstream changed?); removing"
        );
        fs.unlinkSync(jarPath);
      }
    }
  } catch (err) {
    core.warning(
      `oracle jar fetch failed non-fatally: ${(err as Error).message}`
    );
  }
}

/** Run `lake exe sysml check --json`, tolerating a nonzero exit (error findings). */
async function runCheckJson(cwd?: string): Promise<string> {
  const { stdout } = await execCapture("lake", ["exe", "sysml", "check", "--json"], {
    cwd,
  });
  const trimmed = stdout.trim();
  return trimmed.length > 0 ? trimmed : "[]";
}

function writeTemp(name: string, contents: string): string {
  const p = path.join(os.tmpdir(), name);
  fs.writeFileSync(p, contents);
  return p;
}

/** Compute head verdicts in the current (checked-out) workspace. */
async function headVerdicts(): Promise<string> {
  const json = await runCheckJson();
  return writeTemp("sysml-head-verdicts.json", json);
}

/**
 * Compute base verdicts using a git worktree checked out at the PR base sha,
 * so the head workspace is left untouched. Only meaningful on pull_request
 * events, where github.context.payload.pull_request.base.sha is available.
 */
async function baseVerdicts(): Promise<string | undefined> {
  const context = github.context;
  if (context.eventName !== "pull_request") {
    return undefined;
  }

  const pr = context.payload.pull_request;
  const baseSha: string | undefined = pr?.base?.sha;
  if (!baseSha) {
    core.warning("pull_request event missing base sha; skipping base verdicts");
    return undefined;
  }

  await exec.exec("git", ["fetch", "origin", baseSha]);

  const worktreeDir = fs.mkdtempSync(
    path.join(os.tmpdir(), "sysml-base-")
  );
  // git worktree add refuses to reuse an existing empty dir in some git
  // versions; remove it first and let git create it fresh.
  fs.rmdirSync(worktreeDir);

  await exec.exec("git", ["worktree", "add", worktreeDir, baseSha]);

  try {
    const json = await runCheckJson(worktreeDir);
    return writeTemp("sysml-base-verdicts.json", json);
  } finally {
    await exec.exec("git", ["worktree", "remove", "--force", worktreeDir], {
      ignoreReturnCode: true,
    });
  }
}

interface DiffResult {
  markdown: string;
  exitCode: number;
  introduced: number;
  fixed: number;
}

/** Run `lake exe sysml diff base.json head.json --markdown` and parse counts. */
async function diffVerdicts(
  basePath: string,
  headPath: string
): Promise<DiffResult> {
  const { stdout, exitCode } = await execCapture("lake", [
    "exe",
    "sysml",
    "diff",
    basePath,
    headPath,
    "--markdown",
  ]);

  let introduced = 0;
  let fixed = 0;
  for (const line of stdout.split("\n")) {
    const introducedMatch = line.match(/-\s*introduced\s*\((\d+)\)/i);
    if (introducedMatch) {
      introduced += parseInt(introducedMatch[1], 10);
      continue;
    }
    const fixedMatch = line.match(/-\s*fixed\s*\((\d+)\)/i);
    if (fixedMatch) {
      fixed += parseInt(fixedMatch[1], 10);
    }
  }

  return { markdown: stdout, exitCode, introduced, fixed };
}

async function postComment(
  inputs: Inputs,
  diff: DiffResult
): Promise<void> {
  const context = github.context;
  const pr = context.payload.pull_request;
  if (!pr) {
    core.notice("no pull_request in payload; skipping comment.");
    return;
  }

  const octokit = github.getOctokit(inputs.githubToken);
  const regressed = diff.exitCode !== 0;

  const body = [
    STICKY_MARKER,
    diff.markdown,
    "",
    regressed
      ? "⛔ **error findings introduced — the analysis regressed.**"
      : "✅ no error findings introduced.",
  ].join("\n");

  await upsertStickyComment({
    octokit,
    owner: context.repo.owner,
    repo: context.repo.repo,
    issueNumber: pr.number,
    body,
  });
}

async function run(): Promise<void> {
  const inputs = getInputs();
  const startDir = process.cwd();

  try {
    if (inputs.workingDirectory && inputs.workingDirectory !== ".") {
      process.chdir(inputs.workingDirectory);
    }

    await ensureLean(inputs);
    await maybeFetchOracle(inputs);

    const headPath = await headVerdicts();
    core.setOutput("verdicts-path", headPath);

    const context = github.context;
    if (context.eventName !== "pull_request") {
      core.setOutput("regressed", "false");
      core.setOutput("introduced", "0");
      core.setOutput("fixed", "0");
      core.notice(
        "not a pull_request event; skipping base diff and PR comment (only head verdicts were computed)."
      );
      return;
    }

    const basePath = await baseVerdicts();
    if (!basePath) {
      core.setOutput("regressed", "false");
      core.setOutput("introduced", "0");
      core.setOutput("fixed", "0");
      core.notice("could not determine base verdicts; skipping diff and comment.");
      return;
    }

    const diff = await diffVerdicts(basePath, headPath);
    const diffMarkdownPath = writeTemp("sysml-diff.md", diff.markdown);
    const regressed = diff.exitCode !== 0;

    core.setOutput("regressed", regressed ? "true" : "false");
    core.setOutput("introduced", String(diff.introduced));
    core.setOutput("fixed", String(diff.fixed));
    core.setOutput("diff-markdown-path", diffMarkdownPath);

    if (inputs.comment) {
      await postComment(inputs, diff);
    }

    if (regressed && inputs.failOnRegression) {
      core.setFailed(
        `STPA findings regressed: ${diff.introduced} finding(s) introduced (including error severity), ${diff.fixed} fixed.`
      );
    }
  } catch (err) {
    core.setFailed((err as Error).message);
  } finally {
    process.chdir(startDir);
  }
}

run();
