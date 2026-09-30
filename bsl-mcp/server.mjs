#!/usr/bin/env node
/**
 * bsl-check-mcp — MCP-сервер (stdio) для проверки отредактированных файлов 1С (.bsl)
 * через BSL Language Server в Docker на VM.
 *
 * Как работает:
 *  1) клиент (OpenCode) передаёт список файлов (Windows-пути) и/или каталог;
 *  2) MCP переводит пути в VM-пути (через карту WSL_MAP для SMB-шары),
 *     либо копирует файлы на VM по SCP (в inbox);
 *  3) на VM вызывается bsl-check.sh (analyze) — отчёты кладутся в VM_REPORT_DIR;
 *  4) MCP читает bsl-json.json по SSH и возвращает его как JSON.
 *
 * Транспорт: stdio. Инструменты:
 *   check_files   — проверить явный список файлов
 *   check_dir     — проверить каталог
 *   read_report   — прочитать последний отчёт
 */

import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import fs from "node:fs";
import path from "node:path";
import { Readable } from "node:stream";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ---------- конфигурация ----------
function loadConfig() {
  const cfg = {
    SSH_HOST: process.env.SSH_HOST || "kali",
    SSH_KEY: process.env.SSH_KEY || "C:\\Users\\lega\\.ssh\\opencode_vm",
    SSH_BIN: process.env.SSH_BIN || "C:\\Program Files\\Git\\usr\\bin\\ssh.exe",
    SCP_BIN: process.env.SCP_BIN || "C:\\Program Files\\Git\\usr\\bin\\scp.exe",
    VM_BSL_DIR: process.env.VM_BSL_DIR || "/home/kali/bsl-docker",
    VM_REPORT_DIR: process.env.VM_REPORT_DIR || "/srv/bsl-reports",
    WSL_MAP: process.env.WSL_MAP || "E:\\rep=/srv/rep",
    VM_TMP_DIR: process.env.VM_TMP_DIR || "/home/kali/bsl-inbox",
    TIMEOUT_MS: parseInt(process.env.TIMEOUT_MS || "900000", 10),
    KEEP_STAGED: String(process.env.KEEP_STAGED || "false").toLowerCase() === "true",
  };
  const cfgFile = path.join(__dirname, "config.env");
  if (fs.existsSync(cfgFile)) {
    for (const line of fs.readFileSync(cfgFile, "utf8").split(/\r?\n/)) {
      const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/);
      if (!m) continue;
      const [, key, val] = m;
      if (process.env[key] === undefined) cfg[key] = val;
    }
    cfg.TIMEOUT_MS = parseInt(cfg.TIMEOUT_MS, 10);
    cfg.KEEP_STAGED = String(cfg.KEEP_STAGED).toLowerCase() === "true";
  }
  return cfg;
}

const CONFIG = loadConfig();

// ---------- утилиты ----------
function log(...args) {
  process.stderr.write(`[bsl-check-mcp] ${args.join(" ")}\n`);
}

function shQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

function winToPosix(p) {
  let s = String(p).trim();
  if (!s) return s;
  if (s.startsWith("\\\\?\\")) s = s.slice(4);
  s = s.replace(/\\/g, "/");
  const m = s.match(/^([A-Za-z]):(\/.*)?$/);
  if (m) return `/${m[1].toLowerCase()}${m[2] || ""}`;
  return s;
}

function parseMappings(raw) {
  const out = [];
  for (const pair of String(raw).split(",")) {
    const [w, l] = pair.split("=");
    if (!w || !l) continue;
    out.push({ win: winToPosix(w).replace(/\/+$/, ""), lin: l.replace(/\/+$/, "") });
  }
  return out;
}

const MAPPINGS = parseMappings(CONFIG.WSL_MAP);

/** Windows-путь -> VM-путь, если он подпадает под карту SMB-шары. */
function mapToVm(winPath) {
  const p = winToPosix(winPath);
  for (const m of MAPPINGS) {
    if (p === m.win || p.startsWith(m.win + "/")) {
      return { vmPath: m.lin + p.slice(m.win.length), mapped: true };
    }
  }
  return { vmPath: null, mapped: false };
}

function run(cmd, args, { input = null, timeout = CONFIG.TIMEOUT_MS } = {}) {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, { windowsHide: true });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill();
      resolve({ code: -1, stdout, stderr: stderr + `\n[timeout ${timeout} ms]` });
    }, timeout);
    child.stdout.on("data", (d) => (stdout += d.toString()));
    child.stderr.on("data", (d) => (stderr += d.toString()));
    child.on("error", (e) => {
      clearTimeout(timer);
      resolve({ code: -1, stdout, stderr: stderr + String(e) });
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ code, stdout, stderr });
    });
    if (input != null) {
      child.stdin.write(input);
      child.stdin.end();
    }
  });
}

function sshArgs() {
  // Команду передаём в stdin (`bash -s`), чтобы Windows не портил кавычки/UTF-8 в аргументах.
  return [
    "-i",
    CONFIG.SSH_KEY,
    "-o",
    "StrictHostKeyChecking=no",
    "-o",
    "ConnectTimeout=15",
    `${CONFIG.SSH_HOST}`,
    "bash -s",
  ];
}

async function sshExec(remoteCommand, opts = {}) {
  return run(CONFIG.SSH_BIN, sshArgs(), { input: remoteCommand, ...opts });
}

async function scpToVm(localPath, remotePath) {
  log("scp: " + localPath + " -> " + remotePath);
  return run(CONFIG.SCP_BIN, [
    "-i",
    CONFIG.SSH_KEY,
    "-o",
    "StrictHostKeyChecking=no",
    localPath,
    `${CONFIG.SSH_HOST}:${remotePath}`,
  ]);
}

async function ensureRemoteDir(dir) {
  return sshExec(`mkdir -p ${shQuote(dir)}`);
}

// ---------- основная логика ----------
async function stageAndCheck({ files = [], dirs = [], reporters } = {}) {
  const rep = reporters && reporters.length ? reporters : ["json"];
  const errors = [];
  const targets = []; // VM-каталоги/файлы для bsl-check.sh

  // 1) каталоги: только если они отображены на VM (общая папка)
  for (const d of dirs) {
    const { vmPath, mapped } = mapToVm(d);
    if (!mapped) {
      errors.push(`Каталог вне WSL_MAP, пропущен: ${d}`);
      continue;
    }
    targets.push(vmPath);
  }

  // 2) файлы: если файл под WSL_MAP — проверяем на месте; иначе копируем в inbox
  const stagedDirs = new Set();
  const stagedFiles = [];
  for (const f of files) {
    const { vmPath, mapped } = mapToVm(f);
    if (mapped) {
      targets.push(vmPath);
      continue;
    }
    if (!fs.existsSync(f)) {
      errors.push(`Файл не найден: ${f}`);
      continue;
    }
    stagedFiles.push(f);
  }

  if (stagedFiles.length) {
    const stamp = new Date().toISOString().replace(/[-:T]/g, "").slice(0, 14);
    const stageDir = `${CONFIG.VM_TMP_DIR}/${stamp}`;
    await ensureRemoteDir(stageDir);
    for (const f of stagedFiles) {
      const r = await scpToVm(f, `${stageDir}/`);
      if (r.code !== 0) {
        errors.push(`Не удалось скопировать ${f}: ${r.stderr.trim()}`);
      }
    }
    stagedDirs.add(stageDir);
    targets.push(stageDir);
  }

  if (!targets.length) {
    return { ok: false, error: "Нечего проверять", details: errors };
  }

  // 3) проверка на VM: один вызов bsl-check.sh со всеми путями.
  //    Команду собираем heredoc'ом и шлём в stdin — UTF-8 пути не портятся.
  const repArgs = rep.map((r) => shQuote(r)).join(" ");
  const pathArgs = targets.map((t) => shQuote(t)).join(" ");
  const script =
    `cd ${shQuote(CONFIG.VM_BSL_DIR)}\n` +
    `REPORT_DIR=${shQuote(CONFIG.VM_REPORT_DIR)} ./bsl-check.sh ${pathArgs} ${repArgs}\n`;
  const r = await sshExec(script);
  const results = [
    {
      exitCode: r.code,
      stderrTail: r.stderr ? r.stderr.trim().split("\n").slice(-8).join("\n") : "",
    },
  ];

  // 4) читаем отчёт
  const reportPath = `${CONFIG.VM_REPORT_DIR}/bsl-json.json`;
  const cat = await sshExec(`cat ${shQuote(reportPath)}`);
  let report = null;
  try {
    report = JSON.parse(cat.stdout);
  } catch (e) {
    errors.push(`Не удалось прочитать отчёт (${reportPath}): ${String(e).slice(0, 200)}`);
  }

  // 5) уборка staged-каталогов
  if (!CONFIG.KEEP_STAGED) {
    for (const d of stagedDirs) {
      await sshExec(`rm -rf ${shQuote(d)}`);
    }
  }

  return { ok: report !== null, reportPath, targets, results, errors, report };
}

// ---------- MCP ----------
const TOOLS = [
  {
    name: "check_files",
    description:
      "Проверить список отредактированных файлов 1С (.bsl) через BSL Language Server в Docker " +
      "на VM и вернуть JSON-отчёт. Файлы из SMB-шары проверяются на месте, остальные копируются на VM.",
    inputSchema: {
      type: "object",
      properties: {
        files: {
          type: "array",
          items: { type: "string" },
          description: "Абсолютные пути к файлам (Windows), напр. E:\\rep\\...\\Module.bsl",
        },
        reporters: {
          type: "array",
          items: { type: "string" },
          description: "Репортеры BSL: json (по умолчанию), console, junit, tslint, generic",
        },
      },
      required: ["files"],
    },
  },
  {
    name: "check_dir",
    description: "Проверить каталог с исходниками 1С (.bsl) на VM и вернуть JSON-отчёт.",
    inputSchema: {
      type: "object",
      properties: {
        dir: { type: "string", description: "Абсолютный путь к каталогу (Windows)" },
        reporters: { type: "array", items: { type: "string" } },
      },
      required: ["dir"],
    },
  },
  {
    name: "read_report",
    description: "Прочитать последний JSON-отчёт BSL Language Server с VM.",
    inputSchema: { type: "object", properties: {} },
  },
];

const server = new Server(
  { name: "bsl-check-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;

  try {
    if (name === "check_files") {
      const res = await stageAndCheck({ files: args.files || [], reporters: args.reporters });
      return { content: [{ type: "text", text: JSON.stringify(res, null, 2) }], isError: !res.ok };
    }
    if (name === "check_dir") {
      const res = await stageAndCheck({ dirs: [args.dir], reporters: args.reporters });
      return { content: [{ type: "text", text: JSON.stringify(res, null, 2) }], isError: !res.ok };
    }
    if (name === "read_report") {
      const cat = await sshExec(`cat ${shQuote(CONFIG.VM_REPORT_DIR + "/bsl-json.json")}`);
      const isJson = (() => {
        try {
          JSON.parse(cat.stdout);
          return true;
        } catch {
          return false;
        }
      })();
      return {
        content: [{ type: "text", text: isJson ? cat.stdout : JSON.stringify({ ok: false, error: cat.stderr || cat.stdout }) }],
        isError: !isJson,
      };
    }
    return {
      content: [{ type: "text", text: JSON.stringify({ error: `Неизвестный инструмент: ${name}` }) }],
      isError: true,
    };
  } catch (e) {
    log("unhandled error:", String(e));
    return {
      content: [{ type: "text", text: JSON.stringify({ ok: false, error: String(e) }) }],
      isError: true,
    };
  }
});

async function main() {
  // SDK читает stdin как Buffer и сам декодирует UTF-8 — setEncoding не нужен
  // (и вреден: ReadBuffer ожидает Buffer).
  const transport = new StdioServerTransport();
  await server.connect(transport);
  log(
    `started; ssh=${CONFIG.SSH_HOST}, bslDir=${CONFIG.VM_BSL_DIR}, ` +
      `map=[${MAPPINGS.map((m) => m.win + "->" + m.lin).join(", ")}]`,
  );
}

main().catch((e) => {
  log("fatal:", String(e));
  process.exit(1);
});
