import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

function projectFile(path: string): string {
  return readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
}

test("Docker build context excludes credentials, keys, dumps and Git metadata", () => {
  const ignored = new Set(projectFile(".dockerignore").split(/\r?\n/).map((line) => line.trim()));
  for (const required of [".env", ".env.*", ".git", "*.pem", "*.key", "*.dump", "*.tar.gz"]) {
    assert.ok(ignored.has(required), `.dockerignore must contain ${required}`);
  }
});

test("CI workflow actions are pinned to immutable commit SHAs", () => {
  const workflows = projectFile(".github/workflows/ci.yml");
  assert.doesNotMatch(workflows, /uses:\s+actions\/(?:checkout|setup-node)@v\d+/);
  const officialActions = [...workflows.matchAll(/uses:\s+actions\/(?:checkout|setup-node)@([^\s#]+)/g)];
  assert.ok(officialActions.length >= 2);
  officialActions.forEach((match) => assert.match(match[1], /^[0-9a-f]{40}$/));
});

test("the application container is read-only and isolated from the public database surface", () => {
  const dockerfile = projectFile("Dockerfile");
  const compose = projectFile("docker-compose.yml");
  const installer = projectFile("scripts/install-vps.sh");
  assert.doesNotMatch(`${dockerfile}\n${compose}`, /(?:FROM|image:)\s+[^\s@]+(?=\s|$)/);
  assert.match(dockerfile, /node:22-bookworm-slim@sha256:[0-9a-f]{64}/);
  assert.match(compose, /postgres:17-alpine@sha256:[0-9a-f]{64}/);
  assert.match(compose, /caddy:2-alpine@sha256:[0-9a-f]{64}/);
  assert.match(installer, /node:22-bookworm-slim@sha256:[0-9a-f]{64}/);
  assert.match(compose, /read_only:\s*true/);
  assert.match(compose, /no-new-privileges:true/);
  assert.match(compose, /cap_drop:\s*\n\s*- ALL/);
  assert.match(compose, /cap_add:\s*\n\s*- NET_BIND_SERVICE/);
  assert.match(compose, /backend:\s*\n\s*internal:\s*true/);
});

test("self-hosted updates require an explicit release tag", () => {
  const update = projectFile("scripts/update-vps.sh");
  const deploy = projectFile("scripts/deploy-release.sh");
  assert.doesNotMatch(update, /ref="\$\{1:-main\}"/);
  assert.match(update, /Укажите проверенный тег релиза/);
  assert.match(update, /не является аннотированным релизным тегом/);
  assert.match(deploy, /Release archive contains a link, device or another unsupported entry type/);
  assert.match(deploy, /chmod 644 "\$PROJECT_DIR\/Caddyfile"/);
  assert.match(deploy, /http:\/\/127\.0\.0\.1:2019\/config\//);
  assert.match(deploy, /Restoring the previous release/);
});

test("new VPS installations enable security updates and provide an SSH key-only policy", () => {
  const installer = projectFile("scripts/install-vps.sh");
  const sshPolicy = projectFile("deploy/ssh/99-inst_dm-hardening.conf");
  assert.match(installer, /unattended-upgrades/);
  assert.match(installer, /apt-daily-upgrade\.timer/);
  assert.match(installer, /24\.04\|26\.04/);
  assert.match(installer, /chmod 644 "\$PROJECT_DIR\/Caddyfile"/);
  assert.match(sshPolicy, /PasswordAuthentication no/);
  assert.match(sshPolicy, /KbdInteractiveAuthentication no/);
  assert.match(sshPolicy, /PermitRootLogin prohibit-password/);
});

test("domain-only installation docs and release version stay aligned", () => {
  const readme = projectFile("README.md");
  const installRu = projectFile("docs/INSTALL-RU.md");
  const aiInstall = projectFile("docs/AI-INSTALL.md");
  const installer = projectFile("scripts/install-vps.sh");
  const packageVersion = JSON.parse(projectFile("package.json")).version as string;
  const docs = `${readme}\n${installRu}\n${aiInstall}`;

  assert.doesNotMatch(docs, /PUBLIC_IP|ВАШ_IP|sslip\.io|домен не нужен/i);
  assert.match(installer, /укажите собственный домен, а не IP-адрес/);
  assert.match(installer, /A-запись .* ожидается IP этого VPS/);
  for (const document of [readme, installRu, aiInstall]) {
    assert.match(document, new RegExp(`v${packageVersion.replaceAll(".", "\\.")}`));
    assert.match(document, /Ubuntu 24\.04[\s\S]*Ubuntu 26\.04/);
  }
});

test("the env generator replaces the placeholder domain that .env.example actually uses", () => {
  const example = projectFile(".env.example");
  const generator = projectFile("scripts/generate-env.mjs");
  const placeholder = generator.match(/\.replaceAll\("([^"]+)", domain\)/)?.[1];
  assert.ok(placeholder, "generate-env.mjs must substitute a placeholder domain");
  const escaped = placeholder.replaceAll(".", "\\.");
  assert.match(example, new RegExp(`^APP_DOMAIN=${escaped}$`, "m"));
  assert.match(example, new RegExp(`^PUBLIC_BASE_URL=https://${escaped}$`, "m"));
});

test("small 1 vCPU / 2 GB VPS installs get a persistent swap file for the build", () => {
  const installer = projectFile("scripts/install-vps.sh");
  assert.match(installer, /cpu_count >= 1/);
  assert.match(installer, /swapon --noheadings --show=NAME/);
  assert.match(installer, /mkswap \/swapfile/);
  assert.match(installer, /\/swapfile none swap sw 0 0/);
});

test("the README hands AI agents the raw install protocol", () => {
  const readme = projectFile("README.md");
  assert.match(readme, /https:\/\/raw\.githubusercontent\.com\/musa1756\/inst_dm\/main\/docs\/AI-INSTALL\.md/);
  assert.ok(projectFile("docs/AI-INSTALL.md").length > 0);
});
