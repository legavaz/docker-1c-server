#!/usr/bin/env node
/**
 * bsl-check MCP (stdio) — тонкий HTTP-клиент к центральному сервису проверки BSL.
 *
 * Инструмент check_bsl:
 *   - files: string[]  — пути к .bsl/.os файлам (Windows), каждый отправляется в POST /check/file
 *   - text, filename   — текст модуля, отправляется в POST /check
 *
 * Настройки — переменные окружения (токен не хранится в файлах проекта):
 *   BSL_SERVICE_URL    — адрес сервиса, по умолчанию http://192.168.1.51:8080
 *   BSL_SERVICE_TOKEN  — общий токен команды (обязателен)
 */

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";

const BASE_URL = (process.env.BSL_SERVICE_URL || "http://192.168.1.51:8080").replace(/\/+$/, "");
const TOKEN = process.env.BSL_SERVICE_TOKEN || "";
const TIMEOUT_MS = parseInt(process.env.BSL_CLIENT_TIMEOUT_MS || "180000", 10);

// Имя пользователя для журнала сервиса: переменная BSL_USER, иначе учётная запись ОС.
function resolveUser() {
  let name = process.env.BSL_USER || process.env.USERNAME || "";
  if (!name) {
    try {
      name = os.userInfo().username;
    } catch {
      name = "";
    }
  }
  name = name.trim().slice(0, 150);
  return name || "неизвестно";
}
const USER_NAME = resolveUser();

function cleanTicket(value) {
  return value ? String(value).trim().slice(0, 50) : undefined;
}

function log(...args) {
  process.stderr.write(`[bsl-check-mcp] ${args.join(" ")}\n`);
}

async function callService(endpointPath, init) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(`${BASE_URL}${endpointPath}`, {
      ...init,
      headers: { Authorization: `Bearer ${TOKEN}`, ...(init.headers || {}) },
      signal: ctrl.signal,
    });
    const text = await res.text();
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      body = { detail: text };
    }
    if (!res.ok) {
      const detail = typeof body.detail === "string" ? body.detail : JSON.stringify(body.detail);
      throw new Error(`HTTP ${res.status}: ${detail}`);
    }
    return body;
  } finally {
    clearTimeout(timer);
  }
}

async function checkFile(filePath, ticket) {
  const data = fs.readFileSync(filePath);
  const form = new FormData();
  form.append("file", new Blob([data]), path.basename(filePath));
  form.append("user", USER_NAME);
  if (ticket) form.append("ticket", ticket);
  return callService("/check/file", { method: "POST", body: form });
}

async function checkText(filename, text, ticket) {
  return callService("/check", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ filename, text, user: USER_NAME, ...(ticket ? { ticket } : {}) }),
  });
}

async function runCheckBsl(args) {
  if (!TOKEN) throw new Error("не задан BSL_SERVICE_TOKEN (переменная окружения)");
  const ticket = cleanTicket(args.ticket);
  const results = [];
  for (const f of args.files || []) {
    try {
      results.push({ input: f, ...(await checkFile(f, ticket)) });
    } catch (e) {
      results.push({ input: f, error: String(e.message || e) });
    }
  }
  if (args.text) {
    try {
      results.push({ input: args.filename || "Module.bsl", ...(await checkText(args.filename || "Module.bsl", args.text, ticket)) });
    } catch (e) {
      results.push({ input: args.filename || "Module.bsl", error: String(e.message || e) });
    }
  }
  if (results.length === 0) throw new Error("укажите files или text");
  return {
    ok: results.every((r) => !r.error),
    valid: results.every((r) => r.error === undefined && r.valid === true),
    results,
  };
}

const TOOLS = [
  {
    name: "check_bsl",
    description:
      "Проверить модуль 1С (BSL) через центральный сервис проверки. Возвращает JSON: " +
      "valid (нет ошибок уровня Error), summary, errors[], warnings[], text (отчёт для людей). " +
      "Передайте либо files (пути к .bsl/.os), либо text + filename.",
    inputSchema: {
      type: "object",
      properties: {
        files: { type: "array", items: { type: "string" }, description: "Абсолютные пути к файлам (Windows)" },
        text: { type: "string", description: "Текст модуля" },
        filename: { type: "string", description: "Имя модуля для text, например Модуль.bsl" },
        ticket: { type: "string", description: "Номер задачи в Jira (необязательно), до 50 символов, например ERP-1234" },
      },
    },
  },
];

const server = new Server({ name: "bsl-check-mcp", version: "2.0.0" }, { capabilities: { tools: {} } });

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;
  if (name !== "check_bsl") {
    return { content: [{ type: "text", text: JSON.stringify({ error: `неизвестный инструмент: ${name}` }) }], isError: true };
  }
  try {
    const res = await runCheckBsl(args);
    return { content: [{ type: "text", text: JSON.stringify(res, null, 2) }], isError: !res.ok };
  } catch (e) {
    return { content: [{ type: "text", text: JSON.stringify({ ok: false, error: String(e.message || e) }) }], isError: true };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  log(`started; service=${BASE_URL}, token=${TOKEN ? "set" : "MISSING"}, user=${USER_NAME}`);
}

main().catch((e) => {
  log("fatal:", String(e));
  process.exit(1);
});
