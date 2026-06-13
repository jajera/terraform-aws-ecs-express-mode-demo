# ECS Express Mode — findings, limitations, and watchouts

Notes from building and operating an ECS Express Mode demo. Intended as source material for a
feature evaluation and walkthrough.

## How to read this document

| If you need… | Start at |
| ------------ | -------- |
| Express vs classic ECS (evaluation) | **§1**, then **§15** checklist |
| Networking / public vs private / subnets | **§3**, **§5** |
| Which URL to use (Express vs ALB DNS vs custom domain) | **§4** |
| Health checks, deploy rollback, “spinning” service | **§7**, symptom table **§16** |
| Security groups, IAM, Bedrock, container image | **§8–§10** |
| Post-deploy verification commands | **§12** |
| Terraform / provider gotchas | **§13** |
| Console navigation | **§17** |
| Create-only fields, delete leftovers, direct API edits | **§18–§21** |
| Non-HTTP workloads, gRPC, ARM | **§22** |

Terraform file references use this repo’s layout (`ecs.tf`, `locals.tf`, `iam.tf`, `vpc.tf`).

### Section index

§1 Express vs classic · §2 Terraform resource · §3 Subnets · §4 URLs · §5 NAT · §6 Cluster · §7 Health checks · §8 Security groups · §9 IAM · §10 Container / Bedrock · §11 Logs · §12 Verification · §13 Terraform · §14 Region · §15 Checklist · §16 Failures · §17 Console · §18 Immutable at create · §19 Delete · §20 Shared responsibility · §21 Ops tuning · §22 Workload boundaries

## Official references

| Topic | Link |
| ----- | ---- |
| Resources Express Mode creates | [express-service-work](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html) |
| Express Mode overview | [express-service-overview](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-overview.html) |
| `access_type` PUBLIC vs PRIVATE on endpoints | [ManagedIngressPath API](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ManagedIngressPath.html) |
| Create Express Gateway Service API | [CreateExpressGatewayService](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_CreateExpressGatewayService.html) |
| Express Mode best practices | [express-service-best-practices](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-best-practices.html) |
| Custom domains (ALB + Route 53 outside Express) | [express-service-advanced-customization](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-advanced-customization.html) |
| Delete Express services (shared vs unique resources) | [express-service-delete-task](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-delete-task.html) |
| Express Mode troubleshooting | [express-service-troubleshooting](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-troubleshooting.html) |
| Bedrock model access (Marketplace / Anthropic FTU) | [model-access](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html) |
| Classic ECS internet connectivity (ALB public + tasks private) | [networking-outbound](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/networking-outbound.html) |
| Container vs ALB health checks (classic ECS) | [healthcheck](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/healthcheck.html) |
| `HealthCheck` API (task definition container field) | [HealthCheck](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_HealthCheck.html) |
| Update Express Gateway Service API | [UpdateExpressGatewayService](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_UpdateExpressGatewayService.html) |
| Terraform resource | [aws_ecs_express_gateway_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_express_gateway_service) |

---

## 1. Express vs classic ECS (overview)

Start here for a feature evaluation or walkthrough. Later sections drill into networking (§3), URLs (§4), health checks (§7), failures (§16), and limits (§18–§22).

### What each model is for

| | **Classic ECS** | **Express Mode** |
| --- | --- | --- |
| **Goal** | Full control over every layer of a container service | Ship a **HTTPS web app on Fargate** with production-ish defaults and minimal inputs |
| **You define** | Cluster, task definition, service, ALB, listeners, target groups, security groups, scaling, certs, routing… | Container **image**, **task execution role**, **infrastructure role** (+ optional task role, subnets, SG, CPU/memory, health path) |
| **AWS wires** | You (or modules) connect the pieces | Express orchestrates the stack ([resources created](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html)) |
| **Typical user** | Platform teams, existing ECS estates, non-HTTP workloads | Developers who want **image → HTTPS URL** quickly |

Both run **Fargate** tasks in **your account**. Express is not a separate runtime — it is a **simplified provisioning path** on top of the same building blocks.

### What Express creates for you

From [express-service-work](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html), an Express Gateway service provisions (among other things):

- ECS **cluster** (often `default`, if you don’t specify one) with Fargate capacity providers
- **Task definition** + **service** (canary deployment, replica scheduling)
- **Application Load Balancer** — HTTPS listener (443), **Host header** listener rules, target group(s)
- **Security groups** — ALB SG + rules toward your task SG (you may supply an additional task SG)
- **Application Auto Scaling** — target tracking (CPU, memory, or ALB request count per target)
- **CloudWatch log group** for the service
- **ACM certificate** + **`*.ecs.<region>.on.aws` application URL**
- **RollbackAlarm** — faulty deployment detection (see §7)
- Service-linked roles for ECS, ELB, and Application Auto Scaling

**Cost note:** Up to **25 Express services** in the same VPC can **share one ALB** (host-based rules), spreading ALB cost. Classic ECS usually gives you one ALB per app unless you design sharing yourself.

### Side-by-side traffic path

**Classic ECS (typical public web app):**

```text
Internet → ALB (you create, public subnets) → target group → tasks (often private subnets + NAT)
           ↑ you choose listener, cert, rules, TG health check, task SG ingress from ALB SG
```

**Express Mode:**

```text
Internet → shared Express ALB (auto) → Host: *.ecs.region.on.aws → target group → tasks (same subnet list you pass)
           ↑ HTTPS + cert + rule + scaling + rollback alarm largely preconfigured
```

**Critical difference:** Express has **one subnet list** for ALB and tasks. Classic ECS lets you put the **ALB in public subnets and tasks in private subnets** (see §3). Express does **not** support that split on a single service.

### Differences that matter in evaluation

| Topic | Classic ECS | Express Mode |
| ----- | ----------- | ------------ |
| **Ingress / TLS** | You create ALB, ACM, listeners, rules | Managed ALB + default **`*.ecs….on.aws`** URL and cert |
| **Custom domain** | Standard ALB + Route 53 pattern | Same ALB, but **manual** listener Host OR + extra ACM cert (§4) — no property on the Express service |
| **Subnet layout** | ALB subnets ≠ task subnets allowed | **Single** `subnets` list — public → internet-facing; private → internal only |
| **NAT / private tasks** | Common for outbound from private tasks | Private subnets → no public IP; **you** add NAT or endpoints for pull/logs/APIs |
| **Health checks** | ALB TG + optional container `healthCheck` in task def | **ALB path only** via `health_check_path`; Tasks tab **Health: Unknown** is normal (§7) |
| **Failed deploy** | Deployment circuit breaker (configurable) | **RollbackAlarm** + automatic rollback when new tasks stay unhealthy (§7) |
| **Task definition** | Explicit resource you own | Created/managed by Express; limited fields via Express API |
| **Load balancer on service** | You attach `load_balancers` on `aws_ecs_service` | Express owns LB config — **not updatable** via Express API on the service |
| **Deployment strategy** | Rolling, blue/green (with setup) | **Canary** by default; strategy not changeable on Express services per AWS docs |
| **Scaling** | You define ASG/ECS scaling policies | Target tracking wired by Express (CPU / memory / ALB request count) |
| **Sidecars / multi-container** | Supported in task definition | **Primary container** focus; renaming default container can break Express updates |
| **Infrastructure IAM** | ELB/ECS permissions via roles you attach | Extra **infrastructure role** (`AmazonECSInfrastructureRoleforExpressGatewayServices`) |
| **Console entry** | Clusters → Services (full ECS model) | Same **plus** Express Mode **create wizard** (create-only — §17) |

### Under the hood — still your resources

Express Mode resources live in **your AWS account** and appear in EC2/ECS consoles (ALB, target groups, listener rules). AWS documents [advanced customization](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-advanced-customization.html) for changes **outside** the Express API (custom domains, listener edits). Treat hand-edits as advanced — Express updates may expect its defaults.

**Walkthrough tip:** After deploy, open **Clusters → service → Resources**. That tab is the map of what Express built (application URL, ALB, target groups, RollbackAlarm) — use it to contrast with the longer resource list you would create for classic ECS.

### When to choose which

**Prefer Express Mode when:**

- You need a **containerized HTTPS web/API** on Fargate quickly
- **Managed URL + TLS + scaling + rollback** outweigh fine-grained ALB control
- **Public-only or VPC-internal-only** ingress (from subnet choice) is enough
- You accept **Host-header routing** on a shared ALB for multiple Express apps in one VPC

**Prefer classic ECS when:**

- **Public ALB + private tasks** (or complex subnet/SG topology) is required
- You need full control of **listeners, path rules, multiple target groups, NLB, Service Connect**, etc.
- **Container-level health checks** in the task definition matter to your ops model
- Workload is **not** a load-balanced HTTP service (workers, batch, Kafka consumers, etc.)
- You already have **Terraform/modules** for the full stack and don’t need Express’s opinionated defaults

See **§15** for a one-page checklist. Deeper limits: **§18–§22**.

---

## 2. Use the right Terraform resource

**Do:** `aws_ecs_express_gateway_service`

**Do not:** `aws_ecs_cluster` + `aws_ecs_task_definition` + `aws_ecs_service` for Express Mode.

Classic `aws_ecs_service` with `awsvpc` requires explicit `network_configuration` (subnets, security groups) and does **not** provision the Express Mode ALB, HTTPS URL, or managed scaling. It also needs separate infrastructure wiring that Express Gateway handles internally.

---

## 3. Subnet type controls everything (main limitation)

Express Mode has **one** `network_configuration.subnets` list. There is **no** separate “ALB subnets vs task subnets” like classic ECS.

| Subnets you pass | ALB scheme | `ingress_paths.access_type` | Task public IP | Reachable from internet? |
| ---------------- | ---------- | ----------------------------- | -------------- | ------------------------ |
| **Public** (route to IGW) | Internet-facing | `PUBLIC` | Enabled (`assignPublicIp`) | Yes |
| **Private** (no IGW route) | Internal | `PRIVATE` | Disabled | No — VPC only |

**Observed behaviour:** With private subnets, the service URL DNS resolved to **private VPC IPs** (e.g. `10.42.x.x`). `curl` from a laptop failed with “Couldn't connect to server” even though the task was Running.

**This project:** `ecs.tf` uses **public subnets** so the endpoint is internet-facing.

**Production pattern you may expect but Express does not support:**

```text
Internet → ALB (public subnets) → tasks (private subnets) → NAT → outbound
```

For that layout, use **classic ECS** (ALB + `aws_ecs_service` + task definition), not Express Mode.

**Watchout:** The **first** Express service in a VPC defines whether the shared Express ALB for that VPC is internet-facing or internal. Plan subnet choice accordingly.

### Additional VPC / subnet gotchas

| Gotcha | Detail |
| ------ | ------ |
| **Default VPC** | If you omit subnets, Express uses **default VPC public subnets** (needs ≥2 AZs, ≥8 free IPs per subnet). This demo uses a **custom VPC** instead. |
| **Second+ service in same VPC** | Subnets must cover **AZs the shared ALB already uses** — mismatch can block new services ([express-service-work](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html)). |
| **Mixed public + private Express in one VPC** | Risky: the **first** service’s subnet type locks ALB as internet-facing or internal for that VPC. A later service with the “wrong” subnet type may not fit. |
| **IPv6 / dual-stack** | If the first service uses IPv6-capable subnets, the shared ALB may be **dual-stack**. AWS recommends planning IPv6 in a **dedicated VPC** if you need it. |
| **Classic + Express same cluster** | Express services can share an ECS **cluster** with non-Express ECS services ([express-service-work](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html)). |

---

## 4. Application URL vs ALB DNS name (and custom domains)

Express Mode gives you **two hostnames** for the same traffic path. They are easy to confuse during a walkthrough.

### Same load balancer, different names

```text
Client
  │
  ├─► https://ec-04256d75….ecs.ap-southeast-2.on.aws/docs     ← Express application URL
  │         Host: ec-04256d75….ecs.ap-southeast-2.on.aws
  │
  └─► https://k8s-xxxx….ap-southeast-2.elb.amazonaws.com/     ← raw ALB DNS name
            Host: k8s-xxxx….elb.amazonaws.com   (usually wrong for routing)
  │
  └── one Application Load Balancer
        └── listener rule (Host header match) → target group → Fargate tasks
```

Express provisions the ALB, HTTPS listener, certificate, target group, and a **unique application URL** on `*.ecs.<region>.on.aws`. That URL is what the ECS console shows as the service endpoint (Service detail → **Resources** → ingress / application URL).

Up to **25 Express services** in the same VPC/network configuration can **share one ALB**. Each service gets its own `*.ecs….on.aws` hostname; the ALB uses **Host header** listener rules to pick the right target group ([Express overview](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-overview.html)).

### When to use the Express application URL

Use `https://<id>.ecs.<region>.on.aws` for **all normal app traffic**.

| Use it for | Example |
| ---------- | ------- |
| Browser | Open `/docs` (Swagger UI) |
| API calls | `POST /analyze`, `GET /health` |
| Sharing a link | Walkthrough audience clicks this URL |
| Verifying a new deploy | `curl` the health path on this hostname |

**Why:** Express creates a listener rule and ACM certificate for this hostname. The client sends the matching `Host` header, so the ALB routes to **your** target group with valid TLS.

**Walkthrough check:** ECS console → **Clusters** → your cluster → **Services** → service name → **Resources** tab. Copy the HTTPS application URL from there (same value as the create-service output / `ingress_paths` endpoint).

### When to use the raw ALB DNS name

Use the ALB name (`….elb.amazonaws.com`) for **infrastructure and DNS plumbing**, not as the link you give to users.

| Use it for | Why |
| ---------- | --- |
| **Route 53 alias target** | Alias records point at the **load balancer object**, not at `ecs.on.aws` ([custom domain guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-advanced-customization.html)) |
| Finding the ALB in the console | Service → **Resources** → load balancer link |
| Debugging routing / shared ALB | See which listener rules and target groups Express created |

**Do not** expect `https://<alb-dns>/docs` to work like the Express URL. Without the Express hostname in the `Host` header, traffic often hits the listener **default action** (fixed response or wrong target) instead of your service.

**Advanced test only** — force the Express hostname onto the ALB DNS:

```bash
curl -fsS \
  -H "Host: ec-04256d75ab0d4ba394bc90a351df08b0.ecs.ap-southeast-2.on.aws" \
  "https://<alb-dns-name>/health"
```

### Custom domain (third hostname)

A friendly name (e.g. `web.example.com`) is a **third** hostname on the **same ALB**:

1. Issue an **ACM certificate** for your domain (same region as the ALB).
2. Edit the Express ALB **listener rule**: keep the existing `*.ecs….on.aws` Host condition; **Add OR** your custom domain ([step-by-step](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-advanced-customization.html)).
3. **Add the ACM certificate** to the ALB HTTPS listener (SNI).
4. Create a **Route 53 A/AAAA alias** record: name = your subdomain, target = **Application Load Balancer** (pick the Express ALB from the list — not a CNAME to the `ecs.on.aws` URL).

Users then browse `https://web.example.com/docs`. The Express URL can still work if you leave it in the listener OR condition.

**Common mistakes:**

| Mistake | Result |
| ------- | ------ |
| Route 53 **CNAME** to `*.ecs….on.aws` only | DNS works; TLS cert is for `ecs.on.aws`, not your domain → browser warning |
| Alias to ALB but skip listener Host + cert | DNS resolves; wrong host or cert error |
| Give users the raw ALB URL | Unreliable routing unless they set `Host` manually |

Express Mode has **no built-in custom-domain property** on the service itself — you customize the ALB and Route 53 after deploy. Underlying resources stay in your account and remain editable ([advanced customization](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-advanced-customization.html)).

### Rule of thumb

| Question | Use |
| -------- | --- |
| Open Swagger or call the API? | **Express application URL** |
| Paste a link for someone to click? | **Express URL** (or custom domain once configured) |
| Create Route 53 records? | **Alias → ALB**; users hit custom domain or keep Express URL |
| Inspect load balancing in the console? | **ALB** from Service → Resources |

---

## 5. No NAT gateway in this demo

The VPC uses **public subnets only** (`vpc.tf`). Express tasks and the ALB both run there; outbound traffic (GHCR, Bedrock, CloudWatch) uses the **internet gateway**, not NAT.

A NAT gateway is only needed if you migrate to classic ECS with **private tasks** — Express Mode does not support ALB-in-public + tasks-in-private on one service.

---

## 6. ECS cluster

Express Mode does **not** require you to create a dedicated cluster. If you omit `cluster` at create time, AWS uses (and auto-creates if needed) the cluster named **`default`**.

| Behaviour | Detail |
| --------- | ------ |
| **Default** | Omit `cluster` → service lands on **`default`**. |
| **Custom name** | Pass a cluster name or ARN **only at create time**; Express does not auto-create arbitrary cluster names. |
| **After create** | `cluster` cannot be changed — replacing the service is required to move clusters. |

**Walkthrough:** **Clusters** → cluster name → **Services**. Either `default` or a name you chose at deploy time.

---

## 7. Health checks — two different things

AWS documents **two separate health mechanisms** for ECS. Express Mode wires only one of them.

### What AWS documents for Express Mode (ALB only)

There is **no** Express doc page titled “container health checks not supported.” The behaviour follows from the **Express API surface** and the **Express user guide**:

| Source | What AWS says |
| ------ | ------------- |
| [CreateExpressGatewayService](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_CreateExpressGatewayService.html) | **`healthCheckPath`** — *“The path on the container that the **Application Load Balancer** uses for health checks… should return HTTP 200 when the application is healthy.”* Default `/ping`. |
| Same API — **`primaryContainer`** | Configurable fields: `image`, `containerPort`, `environment`, `secrets`, `command`, `awsLogsConfiguration`, `repositoryCredentials`. **No `healthCheck` field.** |
| [UpdateExpressGatewayService](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_UpdateExpressGatewayService.html) | Same: `--health-check-path` for ALB; `primaryContainer` has no health-check parameter. |
| [express-service-work](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html) — **Target group defaults** | `health-check-path`, `health-check-enabled: Always enabled`, interval/timeout/thresholds — all **target group** settings. |
| Same page — **Service defaults** | `healthCheckGracePeriodSeconds: 300` — grace period before the scheduler looks at **ELB or Lattice health checks** (not container `healthCheck`). |
| [express-service-best-practices](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-best-practices.html) — **Health checks** | Implement an HTTP endpoint; set path via console or `update-express-gateway-service --health-check-path "/health"`; tune timeouts on the **ALB target group** (`aws elbv2 modify-target-group`). |

**Terraform:** `aws_ecs_express_gateway_service` exposes only `health_check_path` at the service level — not `healthCheck` on `primary_container` (matches the API).

**This demo:** `health_check_path = "/health"` in `ecs.tf` / `local.web.health_check_path`; the app serves `GET /health` on container port `8000`.

### ALB target group health check (what actually gates traffic and deploys)

- Express creates a target group with health checks **always enabled** ([express-service-work](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html)).
- The ALB probes `health_check_path` on the container port (via the Express-managed listener/target group).
- **Verify health here** — not on the Tasks tab:
  - EC2 console → **Target Groups** → **Targets** (healthy / unhealthy + reason)
  - `terraform output -raw health_check_url` then `curl` (see §12)
  - Service **Resources** tab → target groups

A task can be **Running** with ALB target **healthy** while the Tasks tab still shows **Health status: Unknown** — that is consistent with AWS docs (below).

### ECS console “Health status” on Tasks tab (container `healthCheck`)

This column reflects **container-level** `healthCheck` in the **task definition**, not ALB target health.

From [Determine Amazon ECS task health using container health checks](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/healthcheck.html) and the [HealthCheck API](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_HealthCheck.html):

- **`UNKNOWN`** — *“The container health check is being evaluated, **there's no container health check defined**, or Amazon ECS doesn't have the health status of the container.”*
- **`HEALTHY` / `UNHEALTHY`** — only when a `healthCheck` command is defined in the task definition and the agent has evaluated it.

Express Gateway services are created through an API that **does not define** `healthCheck` on the primary container. Express-managed task definitions therefore leave this column at **`Unknown`** — even when the ALB target is healthy and `/health` returns 200.

**Do not treat `Unknown` as “no health check” or “unhealthy”.** For Express, operational health is **ALB target group state** + **`curl` the health URL** (§12).

### Express deployment rollback alarm

Express creates a CloudWatch metric alarm (shown on the service **Resources** tab as **RollbackAlarm**) tied to deployment health. If new tasks fail ALB health checks, the deployment rolls back.

### Deployment “spin” / rollback loop (walkthrough)

This is the failure mode that looks like the service is **stuck spinning** — Timeline events repeat, deployments never reach **steady state**, or the Express URL returns **503**.

**What is actually happening:**

```text
New deployment starts (config/image change)
    → ECS starts new Fargate tasks
    → ALB target group health-checks health_check_path (e.g. /health)
    → Targets stay unhealthy (app not listening, wrong path, or task exits)
    → RollbackAlarm fires
    → Express rolls deployment back to last good revision
    → Timeline may show another attempt — looks like “spinning”
    → Until fixed: 503 or only old revision serves traffic
```

**Not the same as Tasks → Health status `Unknown`.** That column is unrelated (§ above). The gate is **ALB target group health**, not the ECS task health column.

**What you see in the console:**

| Where | Spinning / failing | Healthy deploy |
| ----- | ------------------ | ---------------- |
| **Timeline** | Repeated “deployment failed” / rollback messages | “Service has reached a **steady state**” |
| **Resources → Target groups** | New targets **unhealthy**; may see two TGs during cutover | Both TGs **Active**; targets **healthy** |
| **Resources → RollbackAlarm** | Alarm state **In alarm** during failed deploy | Alarm exists; deploy succeeded |
| **Express URL** | `curl /health` → non-200 or **503** | `curl /health` → **200** |
| **Tasks tab** | Tasks **Starting** then **Stopped** (crash loop); Health status may stay **Unknown** either way | Tasks **Running**; Health status often still **Unknown** (§7) — check target group instead |

Typical timeline: **~3–8 minutes** from deploy start to rollback if new tasks never pass health checks.

**Root causes seen in this demo (in order of debugging):**

| # | Cause | Why `/health` never passes |
| - | ----- | -------------------------- |
| 1 | **Task SG egress-only** (no ingress on container port) | ALB cannot reach port 8000 — targets unhealthy while app may be running |
| 2 | **Container exits on startup** | e.g. `MODEL_ID` validation calls wrong Bedrock API for inference profile IDs (`au.*`) — process dies before listening |
| 3 | **Wrong `health_check_path`** | ALB probes `/ping` (default) but app only has `/health` |
| 4 | **Port mismatch** | `container_port` ≠ port the app listens on |

**Walkthrough debug order:**

1. **EC2 → Target Groups** → select the Express target group(s) from **Resources** → **Targets** tab → health reason.
2. **CloudWatch Logs** → log group for the service → latest stream — stack trace on startup exit?
3. **ECS → service → Tasks** → stopped task → **Stopped reason** / exit code.
4. **`curl -sS "{Express URL}/health"`** — use `-sS` without `-f` while debugging so error bodies are visible.

**When it’s fixed:** Timeline shows steady state, targets healthy, RollbackAlarm clears, Express URL returns 200 on `/health` and `/docs` loads.

---

## 8. Security groups

### Task security group must allow ALB traffic

The task SG needs **ingress on the container port** from the VPC (or from the Express-managed ALB SG). Egress-only SGs cause **unhealthy targets** and no web traffic.

**This project:** ingress TCP `8000` from `vpc_cidr` via `aws_vpc_security_group_ingress_rule.web_from_vpc`.

Express Mode also adds its own ALB security group automatically; do not assume it replaces task ingress rules.

### Do not duplicate egress rules

`aws_security_group` inline `egress` **and** `aws_vpc_security_group_egress_rule` for the same `0.0.0.0/0` rule causes:

```text
InvalidPermission.Duplicate: the specified rule "peer: 0.0.0.0/0, ALL, ALLOW" already exists
```

Use one method only.

---

## 9. IAM — correct roles and policies

| Role | Trust principal | Policy |
| ---- | --------------- | ------ |
| Task execution | `ecs-tasks.amazonaws.com` | `service-role/AmazonECSTaskExecutionRolePolicy` |
| Infrastructure | `ecs.amazonaws.com` | `service-role/AmazonECSInfrastructureRoleforExpressGatewayServices` |
| Bedrock task | `ecs-tasks.amazonaws.com` | Inline Bedrock permissions (see below) |

**Bedrock task role (`iam.tf`):**

- **Foundation model ID** (no `au.` / `global.` prefix): `bedrock:GetFoundationModel` + `bedrock:InvokeModel` on the foundation-model ARN.
- **Inference profile ID** (e.g. `au.anthropic.claude-sonnet-4-6`): `bedrock:GetInferenceProfile` + `bedrock:InvokeModel` on the inference-profile ARN, plus `bedrock:InvokeModel` on destination foundation-model ARNs (with `bedrock:InferenceProfileArn` condition). AU profiles also allow Sydney and Melbourne foundation-model ARNs.

**Wrong policy that failed apply:**

```text
arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForServiceConnectTransportLayerSecurity
```

That is for Service Connect TLS, not Express Gateway.

**Wrong trust principal for task execution:** `ecs.amazonaws.com` (that is for the infrastructure role).

---

## 10. Container image and Bedrock model

- Image: **GHCR** `ghcr.io/platformfuzz/bedrock-image-analyzer:latest` (not ECR). Task execution role does not need ECR pull permissions.
- Listens on **port 8000**; Express `container_port` must match.
- Environment variables set in `ecs.tf` from `local.web` (`locals.tf`):
  - `AWS_DEFAULT_REGION` — Bedrock region (`var.aws_region`)
  - `MODEL_ID` — `local.web.bedrock_model_id` (default `au.anthropic.claude-sonnet-4-6`)
  - `MAX_TOKENS` — `local.web.bedrock_max_tokens` (default `1024`)
- In many regions (including `ap-southeast-2`), Anthropic models require an **inference profile ID** (e.g. `au.*`, `global.*`), not a bare foundation-model ID.
- The container validates `MODEL_ID` at **startup** via `get_inference_profile` (profile IDs) or `get_foundation_model`. If validation fails, the task exits, ALB health checks fail, and Express may roll back the deployment.
- The container **downloads** `image_url` and sends **base64** image bytes to Bedrock (URL sources are not supported on invoke).

### Bedrock model access (account setup, not Terraform IAM)

Model catalog visibility and **`get_inference_profile` at startup** do not guarantee **`invoke_model` works**. Anthropic models often need one-time **account** setup ([model access](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html)):

1. Complete **Anthropic first-time use** (console or `PutUseCaseForModelAccess`) if prompted.
2. Ensure **Marketplace agreement** / model access is active for the foundation model behind your profile.
3. Wait a few minutes after enabling — first invoke can return `AccessDeniedException` with Marketplace wording while access propagates.

**CLI — check whether invoke entitlement exists** (use foundation model ID, strip profile prefix):

```bash
aws bedrock get-foundation-model-availability \
  --region ap-southeast-2 \
  --model-id anthropic.claude-sonnet-4-6
```

Look for `agreementAvailability.status: AVAILABLE`. Then confirm invoke (ground truth):

```bash
aws bedrock-runtime invoke-model \
  --region ap-southeast-2 \
  --model-id au.anthropic.claude-sonnet-4-6 \
  --content-type application/json \
  --accept application/json \
  --cli-binary-format raw-in-base64-out \
  --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":10,"messages":[{"role":"user","content":"Say hi"}]}' \
  /tmp/out.json
```

Once CLI invoke succeeds, the ECS **Bedrock task role** in `iam.tf` is sufficient — Marketplace permissions belong on the **admin identity** that enables the model, not on the task role.

**API routes (FastAPI):**

| Path | Purpose |
| ---- | ------- |
| `GET /health` | ALB health check — returns `{"status":"healthy"}` |
| `POST /analyze` | Demo endpoint — JSON body `{"image_url": "https://..."}` |
| `GET /docs` | Swagger UI (open in browser) |
| `GET /` | **404** — no homepage; use `/docs` |

**Demo image URL** (must return `image/*`, allow server-side GET from AWS — not HTML, not hotlink-blocked):

```text
https://placehold.co/600x400/png
```

Wikimedia and similar CDNs often return **403** when the container fetches the URL; use a demo-friendly host instead.

---

## 11. CloudWatch log group

- Log group is created in Terraform: `/ecs/<name-prefix>-web`.
- `aws_cloudwatch_log_group` does **not** support `force_destroy` (that is an S3 attribute). Use `retention_in_days` and/or `skip_destroy` if needed.
- Check logs when deployments roll back: `aws logs tail /ecs/<name-prefix>-web --since 30m`

---

## 12. Verification after deploy

Use the **Express application URL** from the service (§4), not the raw ALB DNS name.

| Check | Where / how |
| ----- | ----------- |
| Application URL | ECS → cluster → service → **Resources** → HTTPS ingress URL |
| `access_type` | Same Resources view — must be **PUBLIC** for internet access from a laptop |
| Target health | EC2 → Target Groups → Targets, or `curl` `{Express URL}/health` |
| Swagger UI | Browser → `{Express URL}/docs` (root `/` returns 404 — expected) |
| Logs on rollback | CloudWatch → log group for the service task |

**Example checks** (replace `EXPRESS_URL` with `terraform output -raw service_url`):

```bash
EXPRESS_URL="$(terraform output -raw service_url)"

curl -fsS "${EXPRESS_URL}/health"

curl -sS -X POST "${EXPRESS_URL}/analyze" \
  -H "Content-Type: application/json" \
  -d '{"image_url": "https://placehold.co/600x400/png"}'
```

Use `curl -sS` without `-f` on `/analyze` while debugging so JSON error bodies are visible (422 fetch failures, 502 Bedrock errors).

If `access_type` is **PRIVATE**, the Express URL resolves to VPC-internal addresses and will not work from the public internet (see §3).

---

## 13. Terraform / provider watchouts

- **AWS provider:** `>= 6.50.0` for `aws_ecs_express_gateway_service` (see [provider releases](https://github.com/hashicorp/terraform-provider-aws/releases)).
- **`cluster` is create-only:** AWS `UpdateExpressGatewayService` does not accept `cluster` — changing it requires **replacing the service**. The Terraform provider should treat `cluster` as `ForceNew` ([issue #47277](https://github.com/hashicorp/terraform-provider-aws/issues/47277)).
- **Custom domain:** Not a property on `aws_ecs_express_gateway_service` — wire Route 53 + ALB listener manually (§4) or outside Terraform.
- **State drift:** Express may add or adjust ALB rules, target groups, or security group rules outside what Terraform last wrote. Reconcile after console changes or failed applies.
- **`wait_for_steady_state = true`:** Apply waits for the service to stabilise; first deploy can take several minutes. Failed deployments surface as rollback errors after ~3–8 minutes.
- **State after resource type changes:** If switching from `aws_ecs_service` to `aws_ecs_express_gateway_service`, remove stale resources from state before apply.
- **Validation in this repo:** `terraform fmt` and `terraform validate` (CI workflows). No Python tests.

---

## 14. Region and availability

- **ECS Express Mode** launched across AWS commercial Regions (Nov 2025) — confirm for your account/Region if apply fails with an unsupported API.
- Confirm **Bedrock model access** for your model in that Region (§10).
- Default region in this repo: `ap-southeast-2` with `au.anthropic.claude-sonnet-4-6`.
- Use subnets in AZs that are stable for your account (`opt-in-not-required` where applicable).

---

## 15. Quick decision checklist (Express vs classic)

| Need | Express | Classic |
| ---- | ------- | ------- |
| Fast HTTPS web app on Fargate | ✓ Primary fit | Possible, more wiring |
| Minimal config / quick walkthrough | ✓ | ✗ More resources |
| Public ALB + **private** tasks | ✗ One subnet list (§3) | ✓ |
| Custom domain on your brand | Manual ALB + Route 53 (§4) | Standard pattern |
| Full ALB/listener/TG control | Limited via Express API | ✓ |
| Container health in ECS Tasks tab | ✗ Unknown is normal (§7) | ✓ Task def `healthCheck` |
| Non-HTTP / worker services | ✗ Wrong tool | ✓ |
| Shared ALB across many small apps | ✓ Up to 25 / VPC (§1) | You design it |
| gRPC / raw TCP / workers | ✗ (§22) | ✓ |
| Change infrastructure role later | ✗ Replace service (§18) | N/A |

Full comparison: **§1**. Limits: **§18–§22**.

---

## 16. Common failure symptoms

| Symptom | Likely cause |
| ------- | ------------- |
| Service “spinning”; deploy never reaches steady state | ALB health failing → RollbackAlarm → rollback loop (§7) |
| Timeline: deployment completed then rolled back | New tasks unhealthy — see §7 debug order |
| `curl` fails, DNS → `10.42.x.x` | `access_type = PRIVATE` (private subnets) |
| Browser OK on Express URL but raw ALB URL fails | Expected — Host header routing (§4) |
| TLS error on custom domain | ACM cert not on listener, or Route 53 not aliased to ALB (§4) |
| ALB returns 503 | Deployment rolled back; no healthy targets |
| Target group unhealthy | Wrong `health_check_path`, SG blocks port 8000, or app not listening |
| ECS task Health status `Unknown` | **Expected for Express** — no container `healthCheck` in Express API/task def ([healthcheck](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/healthcheck.html)); check **ALB target health** instead (§7) |
| Deployment stuck then rollback / `RollbackAlarm` | New tasks crash on startup — check CloudWatch logs |
| `/analyze` returns 502 with Marketplace / model access message | Account model agreement not complete — see §10; verify with `get-foundation-model-availability` and CLI `invoke-model` |
| `/analyze` returns 503 with model/region message | Wrong `MODEL_ID` for region, or model not available in Bedrock for that region |
| `/analyze` returns 502 “URL sources are not supported” | Old container image — Bedrock requires base64 images; pull current `bedrock-image-analyzer` image |
| `/analyze` returns 422 “Failed to fetch image” | `image_url` blocked server-side (403) or not `image/*` — use a fetch-friendly demo URL |
| `ValidationException` on model ID | Use inference profile ID (e.g. `au.*`) instead of foundation-model ID |
| Container exits before `/health` works | Startup model validation failed (e.g. `get_foundation_model` used with inference profile ID) |
| `Network Configuration must be provided` | Using classic `aws_ecs_service` without `network_configuration` |
| IAM policy 404 on infrastructure role | Wrong managed policy ARN (Service Connect vs Express Gateway) |
| Duplicate SG egress error | Inline egress + `aws_vpc_security_group_egress_rule` on same SG |
| Second Express service fails in same VPC | Subnet AZs don’t match shared ALB coverage (§3) |
| Resources left after destroy | Shared ALB/cluster retained; log groups may persist (§19) |
| Express update overwrote my ALB edit | Conflicting Express API update vs manual change (§20) |

---

## 17. Express Mode console UI

The **Express Mode** item in the ECS left nav is a **create-only wizard** (“Let’s set up your app”). It is not a dashboard of existing services — the form is always blank until you use it to deploy something new.

| Page | Purpose |
| ---- | ------- |
| **Express Mode** (sidebar) | Create a new Express service (image URI, roles, Create button) |
| **Clusters** → cluster name → **Services** | View and manage existing Express services |
| Service detail → **Resources** | **Express application URL**, ALB link, target groups, listener rules, RollbackAlarm, scaling |

Services created via CLI, CloudFormation, or Terraform do **not** appear on the Express Mode wizard page. Open **Clusters** → your cluster → **Services**. Copy the HTTPS application URL from **Resources** (§4) — that is the URL for the walkthrough, not the raw ALB DNS name unless you are configuring Route 53 or debugging routing.

---

## 18. Immutable at create (plan ahead)

Express is easy to **create**, but several choices are **fixed for the life of the service** (replace the service to change them):

| Field / behaviour | After create |
| ----------------- | ------------ |
| **`service_name`** | Create-only ([express-service-work](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html)) |
| **`cluster`** | Not updatable via Update API — replace service ([CLI](https://docs.aws.amazon.com/cli/latest/reference/ecs/update-express-gateway-service.html), [Terraform #47277](https://github.com/hashicorp/terraform-provider-aws/issues/47277)) |
| **`infrastructure_role_arn`** | **Cannot be modified** — new service required |
| **Deployment strategy** | **Canary only** — strategy cannot be changed on Express services |
| **Load balancer config on ECS service** | Not updatable via Express API (edit ALB/TG directly — §20) |
| **Resource tags (via Express create)** | Add at create only |

**Walkthrough:** Pick cluster name, service name, and infrastructure role deliberately on first deploy.

---

## 19. Delete and leftover resources

Deleting an Express service stops tasks and removes resources **unique to that service**. **Shared** infrastructure may remain ([delete guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-delete-task.html)).

| Resource | Usually deleted with last service? |
| -------- | -------------------------------- |
| Target groups, listener rules, scaling policies, RollbackAlarm, service SG | Yes — per service |
| **Shared ALB** | **No** — if other Express (or other) services still use it |
| **ECS cluster** | **No** — if other services remain |
| **`default` cluster** | Never deleted by Express delete |
| **CloudWatch log group** | Often **retained** — best practices note Express log groups may use **Never expire** retention ([best practices](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-best-practices.html)) |
| **ACM cert for `*.ecs….on.aws`** | Review manually after delete |

**Walkthrough:** After `terraform destroy` or console delete, check **Resources** tab during deletion, then audit EC2 (ALBs, target groups), CloudWatch Logs, and ECS clusters for orphans.

---

## 20. Shared responsibility (direct API edits)

Express Mode **does not replace** classic ECS — it orchestrates resources on your behalf ([advanced customization](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-advanced-customization.html)).

| Topic | Behaviour |
| ----- | --------- |
| **No “graduation”** | There is no convert-to-classic button. Full ECS/ALB/ASG APIs always apply to the same resources. |
| **Manual edits persist** | Changes via EC2/ECS/ELB consoles or direct APIs **stick** — Express will **not** revert them unless an Express update **conflicts** (e.g. you set `logDriver` to FireLens, then Express update passes new `awslogs` config). |
| **No conflict validation** | Express does **not** check whether your ALB/TG/task-def edits break routing or health checks — you own fallout. |
| **Stop Express management** | Remove the **Managed tag** from resources, or deny Express APIs via IAM, if you want to prevent further Express updates. |
| **Sidecars** | Add via **new task definition revision** + deploy; Express updates afterward generally preserve your revision unless conflicting ([sidecar example](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-advanced-customization.html)). |

**Walkthrough:** Custom domain (§4) and WAF (§21) are examples of intentional direct ALB edits.

---

## 21. Operational tuning outside the Express API

Many production knobs live on **underlying resources**, not on `CreateExpressGatewayService` / `UpdateExpressGatewayService`:

| Knob | Where to change |
| ---- | ---------------- |
| Target group **health check interval / timeout / thresholds** | EC2 → Target Groups → Edit health check, or `aws elbv2 modify-target-group` ([best practices](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-best-practices.html)) |
| **`healthCheckGracePeriodSeconds`** | Default **300s** on the ECS service ([express-service-work](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html)) — edit service directly |
| **Canary bake time** | ECS service deployment configuration ([best practices](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-best-practices.html)) |
| **Extra scaling policies** | Application Auto Scaling (request count per target, predictive scaling) in addition to Express default |
| **AWS WAF** | Attach a Web ACL to the Express ALB ([best practices](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-best-practices.html)) |
| **ALB access logs** | **Disabled by default** — enable on the ALB if you need them |
| **Many custom-domain certs on one ALB** | Watch ALB **certificate limit** ([advanced customization](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-advanced-customization.html)) |
| **Log retention** | CloudWatch log group — Express default may be **Never expire**; set retention for cost/compliance |

---

## 22. Protocol and workload boundaries

Express Mode targets **HTTPS web/API on Fargate** via an **Application Load Balancer** (HTTP to targets on your container port).

| Workload | Fit with Express |
| -------- | ---------------- |
| **REST / OpenAPI / Swagger** | ✓ Primary fit (this demo) |
| **WebSockets / SSE / long-lived HTTP** | ⚠️ Possible through ALB with **idle timeout** and HTTP semantics — test your client; not Express-specific |
| **gRPC (HTTP/2 to backend)** | ⚠️ **Limited** on ALB — NLB / App Mesh patterns are classic ECS territory |
| **TCP / UDP / non-HTTP** | ✗ Use NLB or classic ECS, not Express |
| **Batch / queue workers** | ✗ No ingress path — wrong tool |
| **Graviton (ARM)** | Express task definition defaults **`X86_64`** ([express-service-work](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html)) — confirm before assuming ARM |
| **Default container port** | Express default **80** if unset — this demo uses **8000** |

**Ingress:** Express provisions **HTTPS on 443** only (no HTTP listener via Express API). Outbound from tasks follows your subnet/SG model (§3, §5).

---

*Last reviewed against ECS Express Mode and Bedrock docs, and this repo’s Terraform layout, June 2026.*
