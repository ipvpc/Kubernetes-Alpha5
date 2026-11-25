const views = {
  overview: { eyebrow: "Platform", title: "Overview" },
  database: { eyebrow: "Storage", title: "Database" },
  proxmox: { eyebrow: "Infrastructure", title: "Proxmox" },
  hosts: { eyebrow: "Infrastructure", title: "Hosts" },
  flow: { eyebrow: "Platform", title: "Flow" },
  cluster: { eyebrow: "Kubernetes", title: "Cluster" },
  software: { eyebrow: "Kubernetes", title: "Software" },
  updates: { eyebrow: "Maintenance", title: "Updates" },
  monitoring: { eyebrow: "Health", title: "Monitoring" },
  services: { eyebrow: "Kubernetes", title: "Services" },
  cicd: { eyebrow: "Delivery", title: "CI/CD" },
};

const state = {
  view: "overview",
  ready: false,
  config: null,
  preview: null,
  database: null,
  checks: null,
  error: "",
  form: null,
  confirm: null,
  serviceEnv: "dev",
};

const roles = [["control_plane", "Control plane"], ["worker", "Worker"]];
const scopes = [["all", "All nodes"], ["control_plane", "Control plane"], ["workers", "Workers"]];
const updateActions = [["unattended-upgrades", "Security upgrades"], ["apt-upgrade", "Full package upgrade"]];
const methods = [["kubeadm", "kubeadm"], ["k3s", "k3s"], ["rke2", "rke2"]];
const runtimes = [["containerd", "containerd"], ["docker", "docker"]];
const cnis = [["flannel", "flannel"], ["calico", "calico"], ["weave", "weave"]];
const serviceTypes = [["ClusterIP", "ClusterIP"], ["NodePort", "NodePort"], ["LoadBalancer", "LoadBalancer"]];
const environments = ["dev", "staging", "prod"];

function esc(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function showNotice(text, kind) {
  const notice = document.querySelector("#notice");
  notice.hidden = !text;
  notice.textContent = text || "";
  notice.className = kind === "error" ? "error" : "ok-note";
}

async function api(method, path, body) {
  const response = await fetch(path, {
    method,
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
    cache: "no-store",
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || `Request failed (${response.status})`);
  return data;
}

function field(label, name, value, options = {}) {
  const type = options.type || "text";
  const extra = options.readonly ? " readonly" : "";
  const required = options.required ? " required" : "";
  return `<label>${esc(label)}<input name="${esc(name)}" type="${esc(type)}" value="${esc(value ?? "")}"${extra}${required}></label>`;
}

function select(label, name, value, options) {
  const choices = options.map(([id, text]) => `<option value="${esc(id)}"${id === value ? " selected" : ""}>${esc(text)}</option>`).join("");
  return `<label>${esc(label)}<select name="${esc(name)}">${choices}</select></label>`;
}

function check(label, name, checked) {
  return `<label class="check"><input name="${esc(name)}" type="checkbox"${checked ? " checked" : ""}> ${esc(label)}</label>`;
}

function area(label, name, value) {
  return `<label class="span-2">${esc(label)}<textarea name="${esc(name)}" rows="4">${esc(value ?? "")}</textarea></label>`;
}

function formActions() {
  return `<div class="form-actions span-2"><button class="btn primary" type="submit">Save</button><button class="btn" type="button" data-action="cancel">Cancel</button></div>`;
}

function openForm(kind, mode, name = "", environment = "") {
  const method = mode === "add" ? "POST" : "PUT";
  const path = mode === "add"
    ? `/api/${kind}`
    : environment
      ? `/api/${kind}/${encodeURIComponent(environment)}/${encodeURIComponent(name)}`
      : `/api/${kind}/${encodeURIComponent(name)}`;
  return `<form class="card form-grid" data-kind="${esc(kind)}" data-method="${method}" data-path="${esc(path)}" autocomplete="off">`;
}

function rowActions(kind, name, environment = "") {
  const env = environment ? ` data-environment="${esc(environment)}"` : "";
  return `<div class="row-actions"><button class="btn" type="button" data-action="edit" data-kind="${esc(kind)}" data-name="${esc(name)}"${env}>Edit</button><button class="btn danger" type="button" data-action="ask-remove" data-kind="${esc(kind)}" data-name="${esc(name)}"${env}>Remove</button></div>`;
}

function confirmBar(kind) {
  if (!state.confirm || state.confirm.kind !== kind) return "";
  return `<p class="confirm">Remove ${esc(state.confirm.name)}? <button class="btn danger" type="button" data-action="confirm-remove">Remove</button> <button class="btn" type="button" data-action="cancel">Cancel</button></p>`;
}

function record() {
  const form = state.form;
  const config = state.config;
  if (!form || form.mode !== "edit") return null;
  if (form.kind === "hosts") return config.hosts.find((item) => item.name === form.name);
  if (form.kind === "software") return config.software.find((item) => item.name === form.name);
  if (form.kind === "updates") return config.updates.find((item) => item.name === form.name);
  if (form.kind === "checks") return config.monitoring.checks.find((item) => item.name === form.name);
  if (form.kind === "pipelines") return config.cicd.pipelines.find((item) => item.name === form.name);
  if (form.kind === "services") return config.services[form.environment].find((item) => item.name === form.name);
  return null;
}

function blank(kind) {
  if (kind === "hosts") {
    return { name: "", address: "", role: "worker", node_name: "", proxmox_node: "", vmid: "", cores: 4, memory_mb: 8192, disk_gb: 80, monitor: true };
  }
  if (kind === "software") return { name: "", version: "latest", scope: "all" };
  if (kind === "updates") return { name: "", cron: "0 3 * * 0", scope: "all", action: "unattended-upgrades", enabled: true };
  if (kind === "checks") return { name: "", url: "https://" };
  if (kind === "pipelines") return { name: "", image: "alpha5/", context: ".", dockerfile: "Dockerfile", environment: "dev", auto_deploy: false };
  return {
    name: "", image: "", image_tag: "latest", replicas: 2, cpu_request: "100m", memory_request: "128Mi",
    cpu_limit: "500m", memory_limit: "512Mi", port: 8080, env: [], enable_ingress: true, ingress_host: "",
    enable_service: true, service_type: "ClusterIP", monitor: true,
  };
}

function activeRecord(kind) {
  if (state.form && state.form.kind === kind) return record() || blank(kind);
  return null;
}

function checksTable() {
  if (!state.checks) return `<p class="meta">Checking reachability from this machine…</p>`;
  if (!state.checks.length) return `<p class="meta">No checks are configured.</p>`;
  const rows = state.checks.map((item) => `
    <tr>
      <td>${esc(item.name)}</td>
      <td>${esc(item.kind)}</td>
      <td><code>${esc(item.target)}</code></td>
      <td class="${item.reachable ? "ok-text" : "warn-text"}">${item.reachable ? "Reachable" : esc(item.detail)}</td>
    </tr>
  `).join("");
  return `<table><thead><tr><th>Name</th><th>Check</th><th>Target</th><th>From here</th></tr></thead><tbody>${rows}</tbody></table>`;
}

function renderOverview() {
  const config = state.config;
  const services = Object.values(config.services).reduce((sum, items) => sum + items.length, 0);
  const controlPlane = config.hosts.filter((host) => host.role === "control_plane").length;
  const monitored = config.hosts.filter((host) => host.monitor).length;
  const schedules = config.updates.filter((item) => item.enabled).length;
  const reachable = !state.checks
    ? "Checking reachability from this machine…"
    : `${state.checks.filter((item) => item.reachable).length} of ${state.checks.length} checks are reachable from this machine.`;
  const method = config.cluster.install_method;
  const install = method === "kubeadm" || method === "k3s"
    ? `ansible-playbook -i ansible/inventory.yml ansible/playbooks/${method}-install.yml`
    : "rke2 is stored in the inventory. Install playbooks in this repo cover kubeadm and k3s.";
  const commands = [
    ["Connect to hosts", "ansible-playbook -i ansible/inventory.yml ansible/playbooks/connect-hosts.yml"],
    ["Build guests on Proxmox", "ansible-playbook -i ansible/inventory.yml ansible/playbooks/proxmox-cluster.yml"],
    ["Install Kubernetes", install],
    ["Install software", "ansible-playbook -i ansible/inventory.yml ansible/playbooks/install-software.yml"],
    ["Schedule updates", "ansible-playbook -i ansible/inventory.yml ansible/playbooks/schedule-updates.yml"],
    ["Install node exporter", "ansible-playbook -i ansible/inventory.yml ansible/playbooks/configure-monitoring.yml"],
    ["Plan Terraform", "terraform -chdir=terraform plan -var-file=../environments/dev/terraform.tfvars"],
  ];
  const database = state.database && state.database.connected
    ? `Settings are stored in PostgreSQL ${state.database.database} on ${state.database.host}${state.database.version ? ` (${state.database.version})` : ""}.`
    : "PostgreSQL is not connected.";
  return `
    <div class="stack">
      <article class="card">
        <p class="kicker">PostgreSQL</p>
        <h2>${state.database && state.database.connected ? "Connected" : "Not connected"}</h2>
        <p>${esc(database)}</p>
      </article>
      <section class="metrics">
        <article class="card metric"><span>Hosts</span><strong>${config.hosts.length}</strong></article>
        <article class="card metric"><span>Control plane</span><strong>${controlPlane}</strong></article>
        <article class="card metric"><span>Services</span><strong>${services}</strong></article>
        <article class="card metric"><span>Monitored</span><strong>${monitored}</strong></article>
        <article class="card metric"><span>Schedules</span><strong>${schedules}</strong></article>
        <article class="card metric"><span>Pipelines</span><strong>${config.cicd.pipelines.length}</strong></article>
      </section>
      <article class="card">
        <p class="kicker">Reachability</p>
        <h2>From this console</h2>
        <p>${esc(reachable)}</p>
        <div class="actions"><button class="btn primary" type="button" data-action="health">Check reachability</button></div>
        ${state.checks ? `<div class="table-wrap">${checksTable()}</div>` : ""}
      </article>
      <article class="card">
        <p class="kicker">Saved files</p>
        <h2>What a change writes</h2>
        <p>Ansible inventory, group variables, Terraform auto variables for dev, staging, and prod, HTTP checks, and the GitHub Actions workflow.</p>
        ${commands.map(([label, command]) => `<div class="command"><span>${esc(label)}</span><code>${esc(command)}</code></div>`).join("")}
      </article>
    </div>
  `;
}

function renderDatabase() {
  const db = state.database || { host: "postgres.alpha5.finance", port: 5432, database: "alpha5", user: "systems", sslmode: "disable", password_set: false, connected: false, error: "" };
  const status = db.connected ? `Connected${db.version ? ` to PostgreSQL ${db.version}` : ""}` : "Not connected";
  return `
    <form class="card form-grid" data-kind="database" data-method="PUT" data-path="/api/database" autocomplete="off">
      <p class="meta span-2">Save the connection here. Proxmox, hosts, cluster, software, updates, monitoring, services, and CI/CD then save into PostgreSQL from their own screens. The password stays in config/database.local.json on this machine.</p>
      <p class="span-2 ${db.connected ? "ok-text" : "warn-text"}">${esc(status)}${db.error ? `. ${esc(db.error)}` : ""}</p>
      ${field("Host", "db_host", db.host, { required: true })}
      ${field("Port", "db_port", db.port, { type: "number", required: true })}
      ${field("Database", "db_name", db.database, { required: true })}
      ${field("User", "db_user", db.user, { required: true })}
      ${select("TLS mode", "db_sslmode", db.sslmode, [["disable", "Disabled (plain TCP)"], ["prefer", "Prefer TLS (allow plain TCP)"], ["require", "Require TLS"]])}
      ${field("Password", "db_password", "", { type: "password" })}
      <p class="meta span-2">${db.password_set ? "A password is already saved for systems. Leave this blank to keep it." : "Enter the password for user systems. It is stored only in config/database.local.json on this machine."}</p>
      <div class="form-actions span-2"><button class="btn primary" type="submit">Save connection</button></div>
    </form>
  `;
}

function renderProxmox() {
  const item = state.config.proxmox;
  return `
    <form class="card form-grid" data-kind="proxmox" data-method="PUT" data-path="/api/proxmox" autocomplete="off">
      <p class="meta span-2">The API token secret stays in the PROXMOX_TOKEN_SECRET environment variable. The console does not store it.</p>
      ${field("API host", "api_host", item.api_host)}
      ${field("API user", "api_user", item.api_user, { required: true })}
      ${field("Token id", "token_id", item.token_id)}
      ${field("Default node", "node", item.node, { required: true })}
      ${field("Storage", "storage", item.storage, { required: true })}
      ${field("Bridge", "bridge", item.bridge, { required: true })}
      ${field("Template", "template", item.template, { required: true })}
      ${field("CIDR prefix", "cidr_prefix", item.cidr_prefix, { type: "number", required: true })}
      ${field("Gateway", "gateway", item.gateway)}
      ${field("Nameserver", "nameserver", item.nameserver, { required: true })}
      <div class="form-actions span-2"><button class="btn primary" type="submit">Save Proxmox</button></div>
    </form>
  `;
}

function hostForm(item, mode) {
  return `
    ${openForm("hosts", mode, item.name)}
      ${field("Name", "name", item.name, { required: true, readonly: mode === "edit" })}
      ${field("Address", "address", item.address, { required: true })}
      ${select("Role", "role", item.role, roles)}
      ${field("Kubernetes node name", "node_name", item.node_name)}
      ${field("Proxmox node", "proxmox_node", item.proxmox_node)}
      ${field("VM ID", "vmid", item.vmid ?? "", { type: "number" })}
      ${field("Cores", "cores", item.cores, { type: "number", required: true })}
      ${field("Memory MB", "memory_mb", item.memory_mb, { type: "number", required: true })}
      ${field("Disk GB", "disk_gb", item.disk_gb, { type: "number", required: true })}
      ${check("Scrape node exporter", "monitor", item.monitor)}
      ${formActions()}
    </form>
  `;
}

function renderHosts() {
  const editing = activeRecord("hosts");
  const rows = state.config.hosts.map((host) => `
    <tr>
      <td>${esc(host.name)}<div class="meta">${esc(host.node_name)}</div></td>
      <td>${esc(host.address)}</td>
      <td>${host.role === "control_plane" ? "Control plane" : "Worker"}</td>
      <td>${esc(host.proxmox_node || "Existing")}</td>
      <td class="num">${esc(host.cores)} / ${esc(host.memory_mb)} MB</td>
      <td>${host.monitor ? "Yes" : "No"}</td>
      <td>${rowActions("hosts", host.name)}</td>
    </tr>
  `).join("");
  return `
    <div class="stack">
      <div class="toolbar">
        <button class="btn primary" type="button" data-action="add" data-kind="hosts">Add host</button>
      </div>
      ${confirmBar("hosts")}
      ${editing ? hostForm(editing, state.form.mode) : ""}
      <section class="table-wrap">
        <table>
          <thead><tr><th>Host</th><th>Address</th><th>Role</th><th>Proxmox</th><th class="num">Size</th><th>Monitor</th><th></th></tr></thead>
          <tbody>${rows || `<tr><td colspan="7">No hosts yet.</td></tr>`}</tbody>
        </table>
      </section>
    </div>
  `;
}

function renderCluster() {
  const item = state.config.cluster;
  return `
    <form class="card form-grid" data-kind="cluster" data-method="PUT" data-path="/api/cluster" autocomplete="off">
      <p class="meta span-2">The install method selects the kubeadm or k3s playbook. Package installs stay on the Software page.</p>
      ${field("Cluster name", "name", item.name, { required: true })}
      ${select("Install method", "install_method", item.install_method, methods)}
      ${field("Kubernetes version", "kubernetes_version", item.kubernetes_version, { required: true })}
      ${select("Runtime", "container_runtime", item.container_runtime, runtimes)}
      ${select("CNI", "cni_plugin", item.cni_plugin, cnis)}
      ${field("Pod CIDR", "pod_network_cidr", item.pod_network_cidr, { required: true })}
      ${field("Service CIDR", "service_cidr", item.service_cidr, { required: true })}
      ${field("SSH user", "ansible_user", item.ansible_user, { required: true })}
      ${field("SSH private key", "ssh_private_key_file", item.ssh_private_key_file, { required: true })}
      <div class="form-actions span-2"><button class="btn primary" type="submit">Save cluster</button></div>
    </form>
  `;
}

function softwareForm(item, mode) {
  return `
    ${openForm("software", mode, item.name)}
      ${field("Package", "name", item.name, { required: true, readonly: mode === "edit" })}
      ${field("Version", "version", item.version, { required: true })}
      ${select("Scope", "scope", item.scope, scopes)}
      ${formActions()}
    </form>
  `;
}

function renderSoftware() {
  const editing = activeRecord("software");
  const rows = state.config.software.map((item) => `
    <tr>
      <td>${esc(item.name)}</td>
      <td>${esc(item.version)}</td>
      <td>${esc(item.scope)}</td>
      <td>${rowActions("software", item.name)}</td>
    </tr>
  `).join("");
  return `
    <div class="stack">
      <div class="toolbar"><button class="btn primary" type="button" data-action="add" data-kind="software">Add package</button></div>
      ${confirmBar("software")}
      ${editing ? softwareForm(editing, state.form.mode) : ""}
      <section class="table-wrap">
        <table>
          <thead><tr><th>Package</th><th>Version</th><th>Scope</th><th></th></tr></thead>
          <tbody>${rows || `<tr><td colspan="4">No packages yet.</td></tr>`}</tbody>
        </table>
      </section>
    </div>
  `;
}

function updateForm(item, mode) {
  return `
    ${openForm("updates", mode, item.name)}
      ${field("Name", "name", item.name, { required: true, readonly: mode === "edit" })}
      ${field("Cron", "cron", item.cron, { required: true })}
      ${select("Scope", "scope", item.scope, scopes)}
      ${select("Action", "action", item.action, updateActions)}
      ${check("Enabled", "enabled", item.enabled)}
      ${formActions()}
    </form>
  `;
}

function renderUpdates() {
  const editing = activeRecord("updates");
  const rows = state.config.updates.map((item) => `
    <tr>
      <td>${esc(item.name)}</td>
      <td><code>${esc(item.cron)}</code></td>
      <td>${esc(item.scope)}</td>
      <td>${item.action === "apt-upgrade" ? "Full upgrade" : "Security"}</td>
      <td>${item.enabled ? "Enabled" : "Paused"}</td>
      <td>${rowActions("updates", item.name)}</td>
    </tr>
  `).join("");
  return `
    <div class="stack">
      <div class="toolbar"><button class="btn primary" type="button" data-action="add" data-kind="updates">Add schedule</button></div>
      ${confirmBar("updates")}
      ${editing ? updateForm(editing, state.form.mode) : ""}
      <section class="table-wrap">
        <table>
          <thead><tr><th>Schedule</th><th>Cron</th><th>Scope</th><th>Action</th><th>State</th><th></th></tr></thead>
          <tbody>${rows || `<tr><td colspan="6">No schedules yet.</td></tr>`}</tbody>
        </table>
      </section>
    </div>
  `;
}

function checkForm(item, mode) {
  return `
    ${openForm("checks", mode, item.name)}
      ${field("Name", "name", item.name, { required: true, readonly: mode === "edit" })}
      ${field("URL", "url", item.url, { required: true })}
      ${formActions()}
    </form>
  `;
}

function renderMonitoring() {
  const monitoring = state.config.monitoring;
  const editing = activeRecord("checks");
  const derived = [];
  for (const environment of environments) {
    for (const service of state.config.services[environment]) {
      if (service.monitor && service.enable_ingress && service.ingress_host) {
        derived.push(`${environment}-${service.name}`);
      }
    }
  }
  const manual = monitoring.checks.map((item) => `
    <tr><td>${esc(item.name)}</td><td><code>${esc(item.url)}</code></td><td>${rowActions("checks", item.name)}</td></tr>
  `).join("");
  const envChecks = environments.map((environment) => check(environment, `env-${environment}`, monitoring.environments.includes(environment))).join("");
  return `
    <div class="stack">
      <form class="card form-grid" data-kind="monitoring" data-method="PUT" data-path="/api/monitoring" autocomplete="off">
        <p class="meta span-2">Monitored hosts are scraped on port 9100. Grafana is installed in the selected environments on the next Terraform apply.</p>
        ${envChecks}
        ${field("Grafana host", "grafana_host", monitoring.grafana_host, { required: true })}
        ${check("Install Grafana", "grafana", monitoring.grafana)}
        ${check("Publish Grafana ingress", "grafana_ingress", monitoring.grafana_ingress)}
        <div class="form-actions span-2"><button class="btn primary" type="submit">Save monitoring</button></div>
      </form>
      <article class="card">
        <div class="toolbar">
          <h2>Reachability</h2>
          <button class="btn" type="button" data-action="health">Check reachability</button>
        </div>
        ${checksTable()}
      </article>
      <section class="table-wrap">
        <h2>Service health</h2>
        <p class="meta">Derived from services with monitoring and an ingress host: ${esc(derived.join(", ") || "none")}.</p>
        <div class="toolbar"><button class="btn primary" type="button" data-action="add" data-kind="checks">Add HTTP check</button></div>
        ${confirmBar("checks")}
        ${editing ? checkForm(editing, state.form.mode) : ""}
        <table>
          <thead><tr><th>Check</th><th>URL</th><th></th></tr></thead>
          <tbody>${manual || `<tr><td colspan="3">No extra HTTP checks.</td></tr>`}</tbody>
        </table>
      </section>
    </div>
  `;
}

function serviceForm(item, mode) {
  const environment = mode === "edit" ? state.form.environment : state.serviceEnv;
  const envField = mode === "edit"
    ? `<input type="hidden" name="environment" value="${esc(environment)}">`
    : select("Environment", "environment", environment, environments.map((value) => [value, value]));
  return `
    ${openForm("services", mode, item.name, environment)}
      ${envField}
      ${field("Name", "name", item.name, { required: true, readonly: mode === "edit" })}
      ${field("Image", "image", item.image, { required: true })}
      ${field("Tag", "image_tag", item.image_tag, { required: true })}
      ${field("Replicas", "replicas", item.replicas, { type: "number", required: true })}
      ${field("Port", "port", item.port, { type: "number", required: true })}
      ${field("CPU request", "cpu_request", item.cpu_request, { required: true })}
      ${field("CPU limit", "cpu_limit", item.cpu_limit, { required: true })}
      ${field("Memory request", "memory_request", item.memory_request, { required: true })}
      ${field("Memory limit", "memory_limit", item.memory_limit, { required: true })}
      ${select("Service type", "service_type", item.service_type, serviceTypes)}
      ${field("Ingress host", "ingress_host", item.ingress_host)}
      ${check("Expose a Service", "enable_service", item.enable_service)}
      ${check("Expose ingress", "enable_ingress", item.enable_ingress)}
      ${check("HTTP health check", "monitor", item.monitor)}
      ${area("Environment variables", "env", (item.env || []).map((pair) => `${pair.key}=${pair.value}`).join("\n"))}
      ${formActions()}
    </form>
  `;
}

function renderServices() {
  const services = state.config.services[state.serviceEnv];
  const editing = state.form && state.form.kind === "services" ? (record() || blank("services")) : null;
  const rows = services.map((service) => `
    <tr>
      <td>${esc(service.name)}</td>
      <td><code>${esc(service.image)}:${esc(service.image_tag)}</code></td>
      <td class="num">${esc(service.replicas)}</td>
      <td class="num">${esc(service.port)}</td>
      <td>${esc(service.ingress_host || "None")}</td>
      <td>${service.monitor ? "Yes" : "No"}</td>
      <td>${rowActions("services", service.name, state.serviceEnv)}</td>
    </tr>
  `).join("");
  const switcher = environments.map((environment) => `<button class="btn${state.serviceEnv === environment ? " primary" : ""}" type="button" data-action="service-env" data-environment="${environment}">${environment}</button>`).join("");
  return `
    <div class="stack">
      <div class="toolbar">
        <div class="env-switch">${switcher}</div>
        <button class="btn primary" type="button" data-action="add" data-kind="services">Add service</button>
      </div>
      ${confirmBar("services")}
      ${editing ? serviceForm(editing, state.form.mode) : ""}
      <section class="table-wrap">
        <table>
          <thead><tr><th>Service</th><th>Image</th><th class="num">Replicas</th><th class="num">Port</th><th>Ingress</th><th>Monitor</th><th></th></tr></thead>
          <tbody>${rows || `<tr><td colspan="7">No services in ${esc(state.serviceEnv)}.</td></tr>`}</tbody>
        </table>
      </section>
    </div>
  `;
}

function pipelineForm(item, mode) {
  return `
    ${openForm("pipelines", mode, item.name)}
      ${field("Name", "name", item.name, { required: true, readonly: mode === "edit" })}
      ${field("Image", "image", item.image, { required: true })}
      ${field("Context", "context", item.context, { required: true })}
      ${field("Dockerfile", "dockerfile", item.dockerfile, { required: true })}
      ${select("Environment", "environment", item.environment, environments.map((value) => [value, value]))}
      ${check("Auto deploy with Terraform", "auto_deploy", item.auto_deploy)}
      ${formActions()}
    </form>
  `;
}

function renderCicd() {
  const cicd = state.config.cicd;
  const editing = activeRecord("pipelines");
  const rows = cicd.pipelines.map((item) => `
    <tr>
      <td>${esc(item.name)}</td>
      <td><code>${esc(cicd.registry)}/${esc(item.image)}</code></td>
      <td>${esc(item.environment)}</td>
      <td>${item.auto_deploy ? "Apply" : "Build only"}</td>
      <td>${rowActions("pipelines", item.name)}</td>
    </tr>
  `).join("");
  return `
    <div class="stack">
      <form class="card form-grid" data-kind="cicd" data-method="PUT" data-path="/api/cicd" autocomplete="off">
        <p class="meta span-2">Auto deploy writes a workflow job that applies Terraform with the KUBE_CONFIG secret. Leave it off until that secret exists.</p>
        ${field("Registry", "registry", cicd.registry, { required: true })}
        ${field("Dev branch", "branch-dev", cicd.branches.dev, { required: true })}
        ${field("Staging branch", "branch-staging", cicd.branches.staging, { required: true })}
        ${field("Prod branch", "branch-prod", cicd.branches.prod, { required: true })}
        <div class="form-actions span-2"><button class="btn primary" type="submit">Save CI/CD</button></div>
      </form>
      <div class="toolbar"><button class="btn primary" type="button" data-action="add" data-kind="pipelines">Add pipeline</button></div>
      ${confirmBar("pipelines")}
      ${editing ? pipelineForm(editing, state.form.mode) : ""}
      <section class="table-wrap">
        <table>
          <thead><tr><th>Pipeline</th><th>Image</th><th>Environment</th><th>Deploy</th><th></th></tr></thead>
          <tbody>${rows || `<tr><td colspan="5">No pipelines yet.</td></tr>`}</tbody>
        </table>
      </section>
    </div>
  `;
}

function flowConfig() {
  return state.config || state.preview;
}

function endpoint(value) {
  const text = String(value ?? "").trim();
  if (!text || text.length > 300 || /\s/.test(text)) return null;
  if (text.includes("://")) {
    try {
      const url = new URL(text);
      if (!url.hostname) return null;
      return { host: url.hostname, port: url.port };
    } catch {
      return null;
    }
  }
  if (!/^[A-Za-z0-9._:-]+$/.test(text)) return null;
  const match = text.match(/^([A-Za-z0-9._-]+):(\d{1,5})$/);
  if (match) return { host: match[1], port: match[2] };
  if (text.includes(".") || text.endsWith("-service")) return { host: text, port: "" };
  return null;
}

function serviceForHost(host, services) {
  return services.find((service) => host === service.name || host === `${service.name}-service` || (service.ingress_host && host === service.ingress_host));
}

function placement(host, service) {
  if (!service.enable_service || service.replicas < 1) return { kind: "off", label: "Off" };
  if (host.role === "worker") return { kind: "runs", label: "Runs" };
  if (host.role === "control_plane") return { kind: "schedules", label: "Schedules" };
  return { kind: "none", label: "—" };
}

function flowEdges(config, environment) {
  const services = config.services[environment] || [];
  const hosts = config.hosts || [];
  const workers = hosts.filter((host) => host.role === "worker");
  const planes = hosts.filter((host) => host.role === "control_plane");
  const cluster = config.cluster;
  const monitoring = config.monitoring;
  const watched = monitoring.environments.includes(environment);
  const edges = [];
  if (planes.length && workers.length) {
    edges.push({
      from: planes.map((host) => host.name).join(", "),
      path: `${cluster.install_method} scheduler`,
      to: workers.map((host) => host.name).join(", "),
      detail: `${cluster.kubernetes_version} · ${cluster.cni_plugin} ${cluster.pod_network_cidr} · services ${cluster.service_cidr}`,
    });
  }
  for (const host of hosts) {
    if (!host.proxmox_node) continue;
    edges.push({
      from: host.proxmox_node,
      path: "Proxmox VM",
      to: `${host.name} ${host.address}`,
      detail: host.vmid ? `VMID ${host.vmid}` : "VMID is not saved",
    });
  }
  const workerLabel = workers.length ? workers.map((host) => host.name).join(", ") : "No worker hosts";
  for (const service of services) {
    const target = `${service.name}:${service.port}`;
    if (service.enable_ingress && service.ingress_host) {
      edges.push({
        from: "Clients",
        path: `HTTPS ${service.ingress_host}`,
        to: target,
        detail: service.service_type,
      });
    }
    if (service.enable_service && service.replicas > 0) {
      edges.push({
        from: target,
        path: service.service_type,
        to: workerLabel,
        detail: `${service.replicas} replicas, shared across workers`,
      });
    }
    for (const pair of service.env || []) {
      const point = endpoint(pair.value);
      if (!point) continue;
      const match = serviceForHost(point.host, services);
      const port = point.port ? `:${point.port}` : "";
      edges.push({
        from: service.name,
        path: pair.key,
        to: match ? `${match.name}${port}` : `${point.host}${port}`,
        detail: match ? "In-cluster service DNS" : "Host saved on the service",
      });
    }
    if (service.monitor && service.enable_ingress && service.ingress_host) {
      edges.push({
        from: "Health checks",
        path: "GET /health",
        to: `https://${service.ingress_host}/health`,
        detail: "monitoring/http-checks.yml",
      });
    }
  }
  if (watched) {
    const targets = hosts.filter((host) => host.monitor).map((host) => `${host.address}:9100`);
    if (targets.length) {
      edges.push({
        from: "Prometheus",
        path: "scrape /metrics",
        to: targets.join(", "),
        detail: "Node exporter on hosts with monitoring on",
      });
    }
    if (monitoring.grafana) {
      edges.push({
        from: monitoring.grafana_ingress ? monitoring.grafana_host : "Grafana",
        path: "reads metrics",
        to: "Prometheus",
        detail: "Installed together for this environment",
      });
    }
  }
  const branch = config.cicd.branches[environment] || "";
  for (const pipeline of config.cicd.pipelines) {
    if (pipeline.environment !== environment) continue;
    const matched = services.filter((service) => service.image === pipeline.image).map((service) => service.name);
    edges.push({
      from: `${branch} · ${config.cicd.registry}`,
      path: pipeline.name,
      to: matched.length ? matched.join(", ") : pipeline.image,
      detail: pipeline.auto_deploy ? "Auto-deploy is on" : "Auto-deploy is off",
    });
  }
  return edges;
}

function renderFlow() {
  const config = flowConfig();
  if (!config) {
    return `<article class="card"><h2>Save the PostgreSQL connection first</h2><p>The flow map reads the saved hosts and services.</p><div class="actions"><button class="btn primary" type="button" data-action="show-database">Open Database</button></div></article>`;
  }
  const environment = state.serviceEnv;
  const services = config.services[environment] || [];
  const hosts = config.hosts || [];
  const watched = config.monitoring.environments.includes(environment);
  const switcher = environments.map((item) => `<button class="btn${environment === item ? " primary" : ""}" type="button" data-action="service-env" data-environment="${item}">${item}</button>`).join("");
  const head = services.map((service) => `<th>${esc(service.name)}<span class="host-meta">${esc(service.replicas)} replicas · :${esc(service.port)}</span></th>`).join("");
  const rows = hosts.map((host) => {
    const cells = services.map((service) => {
      const place = placement(host, service);
      const note = place.kind === "runs"
        ? `${service.replicas} replicas are shared. This host is eligible and is not pinned.`
        : place.kind === "schedules"
          ? "The control plane schedules this service. Pods are not placed here."
          : "This service is off.";
      return `<td><span class="place ${place.kind}" title="${esc(note)}">${esc(place.label)}</span></td>`;
    }).join("");
    const metrics = !host.monitor ? "Off" : watched ? ":9100" : "Not scraped";
    const metricKind = !host.monitor ? "off" : watched ? "runs" : "schedules";
    const role = host.role === "control_plane" ? "Control plane" : "Worker";
    return `<tr><th scope="row"><span class="host-name">${esc(host.name)}</span><span class="host-meta">${esc(role)} · ${esc(host.address)}</span></th>${cells}<td><span class="place ${metricKind}">${esc(metrics)}</span></td></tr>`;
  }).join("");
  const body = rows || `<tr><td colspan="${services.length + 2}">No hosts saved.</td></tr>`;
  const edges = flowEdges(config, environment);
  const flowRows = edges.map((edge) => `<tr><td>${esc(edge.from)}</td><td class="flow-path">${esc(edge.path)}</td><td>${esc(edge.to)}</td><td>${esc(edge.detail)}</td></tr>`).join("");
  const fileNote = state.config ? "" : `<p class="meta">Showing the settings file. Connect PostgreSQL to save later changes into the database.</p>`;
  return `
    <div class="stack">
      <div class="env-switch">${switcher}</div>
      ${fileNote}
      <section class="table-wrap">
        <h2>Hosts and services</h2>
        <p class="meta">Runs means the worker is eligible for pods. Schedules means the control plane places those pods. Replicas are shared and are not pinned to one host. Metrics shows node exporter when this environment collects it.</p>
        ${services.length ? "" : `<p class="meta">No services in ${esc(environment)}.</p>`}
        <table class="matrix" aria-label="Hosts and services in ${esc(environment)}">
          <thead><tr><th>Host</th>${head}<th>Metrics</th></tr></thead>
          <tbody>${body}</tbody>
        </table>
      </section>
      <section class="table-wrap">
        <h2>How data moves</h2>
        <table aria-label="Data flow in ${esc(environment)}">
          <thead><tr><th>From</th><th>Path</th><th>To</th><th>Detail</th></tr></thead>
          <tbody>${flowRows || `<tr><td colspan="4">No connections in ${esc(environment)}.</td></tr>`}</tbody>
        </table>
      </section>
    </div>
  `;
}

const pages = {
  overview: renderOverview,
  database: renderDatabase,
  proxmox: renderProxmox,
  hosts: renderHosts,
  cluster: renderCluster,
  software: renderSoftware,
  updates: renderUpdates,
  monitoring: renderMonitoring,
  services: renderServices,
  flow: renderFlow,
  cicd: renderCicd,
};

function render() {
  const meta = views[state.view];
  document.querySelector("#page-title").textContent = meta.title;
  document.querySelector("#eyebrow").textContent = meta.eyebrow;
  document.querySelectorAll(".nav").forEach((button) => {
    if (button.dataset.view === state.view) button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  });
  const foot = document.querySelector("#sidebar-foot");
  if (state.database && state.database.connected) foot.textContent = `PostgreSQL · ${state.database.database}`;
  else if (state.config) foot.textContent = `${state.config.cluster.name} · ${state.config.hosts.length} hosts`;
  else foot.textContent = state.ready ? "PostgreSQL not connected" : "Loading settings";
  const content = document.querySelector("#content");
  if (!state.ready) {
    content.innerHTML = `<p class="loading">Loading settings…</p>`;
    return;
  }
  if (!state.config && state.view === "flow" && state.preview) {
    content.innerHTML = pages.flow();
    return;
  }
  if (!state.config && state.view !== "database") {
    content.innerHTML = state.error
      ? `<div class="error" role="alert"><p>${esc(state.error)}</p><button class="btn primary" type="button" data-action="reload">Reload</button></div>`
      : `<article class="card"><h2>Save the PostgreSQL connection first</h2><p>The setting screens write to PostgreSQL after the connection is saved.</p><div class="actions"><button class="btn primary" type="button" data-action="show-database">Open Database</button></div></article>`;
    return;
  }
  content.innerHTML = pages[state.view]();
}

function numberValue(form, name, allowEmpty) {
  const raw = form.elements[name].value.trim();
  if (raw === "" && allowEmpty) return null;
  const value = Number(raw);
  if (!Number.isInteger(value)) throw new Error(`${name} must be a whole number`);
  return value;
}

function checked(form, name) {
  return Boolean(form.elements[name] && form.elements[name].checked);
}

function envPairs(text) {
  const pairs = [];
  for (const line of text.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    const index = trimmed.indexOf("=");
    if (index < 1) throw new Error("Each variable must look like KEY=value");
    pairs.push({ key: trimmed.slice(0, index).trim(), value: trimmed.slice(index + 1) });
  }
  return pairs;
}

function payloadFor(form) {
  const kind = form.dataset.kind;
  if (kind === "database") {
    return {
      host: form.elements.db_host.value,
      port: numberValue(form, "db_port"),
      database: form.elements.db_name.value,
      user: form.elements.db_user.value,
      password: form.elements.db_password.value,
      sslmode: form.elements.db_sslmode.value,
    };
  }
  if (kind === "proxmox") {
    return {
      api_host: form.elements.api_host.value,
      api_user: form.elements.api_user.value,
      token_id: form.elements.token_id.value,
      node: form.elements.node.value,
      storage: form.elements.storage.value,
      bridge: form.elements.bridge.value,
      template: form.elements.template.value,
      cidr_prefix: numberValue(form, "cidr_prefix"),
      gateway: form.elements.gateway.value,
      nameserver: form.elements.nameserver.value,
    };
  }
  if (kind === "cluster") {
    return {
      name: form.elements.name.value,
      install_method: form.elements.install_method.value,
      kubernetes_version: form.elements.kubernetes_version.value,
      container_runtime: form.elements.container_runtime.value,
      cni_plugin: form.elements.cni_plugin.value,
      pod_network_cidr: form.elements.pod_network_cidr.value,
      service_cidr: form.elements.service_cidr.value,
      ansible_user: form.elements.ansible_user.value,
      ssh_private_key_file: form.elements.ssh_private_key_file.value,
    };
  }
  if (kind === "hosts") {
    return {
      name: form.elements.name.value,
      address: form.elements.address.value,
      role: form.elements.role.value,
      node_name: form.elements.node_name.value || form.elements.name.value,
      proxmox_node: form.elements.proxmox_node.value,
      vmid: numberValue(form, "vmid", true),
      cores: numberValue(form, "cores"),
      memory_mb: numberValue(form, "memory_mb"),
      disk_gb: numberValue(form, "disk_gb"),
      monitor: checked(form, "monitor"),
    };
  }
  if (kind === "software") {
    return { name: form.elements.name.value, version: form.elements.version.value, scope: form.elements.scope.value };
  }
  if (kind === "updates") {
    return {
      name: form.elements.name.value,
      cron: form.elements.cron.value,
      scope: form.elements.scope.value,
      action: form.elements.action.value,
      enabled: checked(form, "enabled"),
    };
  }
  if (kind === "monitoring") {
    return {
      environments: environments.filter((environment) => checked(form, `env-${environment}`)),
      grafana: checked(form, "grafana"),
      grafana_ingress: checked(form, "grafana_ingress"),
      grafana_host: form.elements.grafana_host.value,
    };
  }
  if (kind === "checks") return { name: form.elements.name.value, url: form.elements.url.value };
  if (kind === "services") {
    return {
      environment: form.elements.environment.value,
      name: form.elements.name.value,
      image: form.elements.image.value,
      image_tag: form.elements.image_tag.value,
      replicas: numberValue(form, "replicas"),
      port: numberValue(form, "port"),
      cpu_request: form.elements.cpu_request.value,
      cpu_limit: form.elements.cpu_limit.value,
      memory_request: form.elements.memory_request.value,
      memory_limit: form.elements.memory_limit.value,
      service_type: form.elements.service_type.value,
      ingress_host: form.elements.ingress_host.value,
      enable_service: checked(form, "enable_service"),
      enable_ingress: checked(form, "enable_ingress"),
      monitor: checked(form, "monitor"),
      env: envPairs(form.elements.env.value),
    };
  }
  if (kind === "cicd") {
    return {
      registry: form.elements.registry.value,
      branches: {
        dev: form.elements["branch-dev"].value,
        staging: form.elements["branch-staging"].value,
        prod: form.elements["branch-prod"].value,
      },
    };
  }
  return {
    name: form.elements.name.value,
    image: form.elements.image.value,
    context: form.elements.context.value,
    dockerfile: form.elements.dockerfile.value,
    environment: form.elements.environment.value,
    auto_deploy: checked(form, "auto_deploy"),
  };
}

async function saveForm(form) {
  let payload;
  try {
    payload = payloadFor(form);
  } catch (error) {
    showNotice(error.message, "error");
    return;
  }
  try {
    const data = await api(form.dataset.method, form.dataset.path, payload);
    if (data.database) state.database = data.database;
    state.config = data.config;
    state.form = null;
    state.confirm = null;
    showNotice(data.message);
    render();
  } catch (error) {
    showNotice(error.message, "error");
  }
}

async function removeCurrent() {
  const item = state.confirm;
  const path = item.environment
    ? `/api/${item.kind}/${encodeURIComponent(item.environment)}/${encodeURIComponent(item.name)}`
    : `/api/${item.kind}/${encodeURIComponent(item.name)}`;
  try {
    const data = await api("DELETE", path);
    if (data.database) state.database = data.database;
    state.config = data.config;
    state.form = null;
    state.confirm = null;
    showNotice(data.message);
    render();
  } catch (error) {
    showNotice(error.message, "error");
  }
}

async function refreshHealth() {
  showNotice("Checking reachability…");
  try {
    state.checks = (await api("GET", "/api/health?fresh=1")).checks;
    showNotice("");
    render();
  } catch (error) {
    showNotice(error.message, "error");
  }
}

async function load() {
  state.error = "";
  try {
    const data = await api("GET", "/api/config");
    state.database = data.database;
    state.config = data.config;
    state.preview = data.preview || null;
    state.ready = true;
    if (!state.config) state.view = "database";
    render();
    if (!state.config) return;
    state.checks = (await api("GET", "/api/health")).checks;
    if (!state.form) render();
  } catch (error) {
    state.ready = true;
    state.error = error.message;
    if (!state.config) {
      state.view = "database";
      render();
    } else showNotice(error.message, "error");
  }
}

document.body.addEventListener("click", (event) => {
  const nav = event.target.closest(".nav");
  if (nav) {
    state.view = nav.dataset.view;
    state.form = null;
    state.confirm = null;
    render();
    return;
  }
  const button = event.target.closest("[data-action]");
  if (!button) return;
  const action = button.dataset.action;
  if (action === "add") {
    state.form = { kind: button.dataset.kind, mode: "add" };
    state.confirm = null;
    render();
    return;
  }
  if (action === "edit") {
    state.form = { kind: button.dataset.kind, mode: "edit", name: button.dataset.name, environment: button.dataset.environment || "" };
    state.confirm = null;
    render();
    return;
  }
  if (action === "ask-remove") {
    state.confirm = { kind: button.dataset.kind, name: button.dataset.name, environment: button.dataset.environment || "" };
    render();
    return;
  }
  if (action === "cancel") {
    state.form = null;
    state.confirm = null;
    render();
    return;
  }
  if (action === "confirm-remove") removeCurrent();
  if (action === "health") refreshHealth();
  if (action === "reload") load();
  if (action === "show-database") {
    state.view = "database";
    state.form = null;
    state.confirm = null;
    render();
  }
  if (action === "service-env") {
    state.serviceEnv = button.dataset.environment;
    state.form = null;
    state.confirm = null;
    render();
  }
});

document.body.addEventListener("submit", (event) => {
  if (!(event.target instanceof HTMLFormElement)) return;
  event.preventDefault();
  saveForm(event.target);
});

render();
load();
