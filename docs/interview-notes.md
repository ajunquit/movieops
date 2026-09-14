# Interview Notes — STAR Stories

Living document. Every real bug, design decision, or pattern we implement gets a short STAR entry here **while it's still fresh** — not reconstructed from memory at Sprint 13. Each entry closes with which questions from [section 54 of the plan](../MovieOps_DevOps_Plan.md) it answers.

Format: **Situation** (context) → **Task** (what needed to happen) → **Action** (what we actually did) → **Result** (outcome + what it proves).

---

## Sprint 3 — TMDB base URL silently dropping a path segment

**Situation:** Integrating TMDB search behind a resilient `HttpClient` (timeout/retry/circuit breaker via `AddStandardResilienceHandler`).

**Task:** Get `GET /api/movies/search?query=batman` to actually return TMDB results.

**Action:** First live test returned a 502 (degraded path working as designed) — but the underlying HTTP log showed the outgoing request as `GET https://api.themoviedb.org/search/movie`, missing the `/3` API version segment. Root cause: `HttpClient.BaseAddress` was set to `"https://api.themoviedb.org/3"` (no trailing slash). Per RFC 3986 URI-combining rules, a base URI without a trailing `/` has its last path segment *replaced* by the relative URI, not appended to — so `/3` + `search/movie` becomes `/search/movie`, silently. Fixed by adding the trailing slash to the base URL.

**Result:** Confirmed with a real TMDB API key: correct URL (`/3/search/movie`), real search results, and — the same test also proved the resilience layer itself works, since the *first* attempt (before the fix, with no API key) returned a controlled 502 via `TmdbUnavailableException`, not a crash.

**Answers:** ¿Cómo hacer resiliente una integración externa? · ¿Cómo diseñar un pipeline seguro? (fail controlado vs. crash) — this is close to the exact STAR example already written in section 53 of the plan.

---

## Sprint 4 — Config resolved "eager", test overrides silently ignored

**Situation:** Wrote integration tests using `WebApplicationFactory` + Testcontainers (real Postgres in a container), overriding `ConnectionStrings:Default` via `ConfigureAppConfiguration`.

**Task:** Get the API under test to actually talk to the Testcontainers Postgres instance, not whatever `appsettings.Development.json` said.

**Action:** Tests failed with `Failed to connect to 127.0.0.1:5432` — the literal value from `appsettings.Development.json`, proving the test's configuration override never took effect. Root cause: `AddInfrastructure(configuration)` read `configuration.GetConnectionString("Default")` **once, eagerly**, at service-registration time (`builder.Services.AddDbContext<T>(options => options.UseNpgsql(connectionString))`), baking in whatever value existed *before* the test factory's `ConfigureAppConfiguration` callback could layer its override on top. Fixed by resolving `IConfiguration` lazily, per-request, inside the `AddDbContext` factory delegate (`(sp, options) => ...`) instead of capturing a plain string.

**Result:** All 3 integration tests pass against a real Postgres container. This wasn't just a test-only fix — it was a latent fragility in the real app too (anything that changes config after DI registration, e.g. layered config sources, would have silently lost the override).

**Answers:** ¿Cómo manejar ambientes? · ¿Qué diferencia hay entre CI y CD? (esto es justo el tipo de bug que solo un test de integración real detecta, no un unit test con mocks).

---

## Sprint 5 — Container reports "unhealthy" while serving traffic perfectly

**Situation:** `docker compose up` with all 3 services; frontend (nginx) container flips to `unhealthy` after several minutes even though `curl http://localhost:4200/` from the host works fine.

**Task:** Figure out why the Docker healthcheck disagrees with reality.

**Action:** Ran the exact healthcheck command (`wget --spider -q http://localhost/`) manually inside the container — it failed with `Connection refused`, while the same request from the *host* succeeded. Diagnosis: inside the container, `wget` resolves `localhost` to `::1` (IPv6) first; nginx's `listen 80;` only binds IPv4 (`0.0.0.0:80`), so the IPv6 attempt is refused outright (BusyBox `wget` doesn't fall back to IPv4 on failure). From the host, Docker's port-forwarding bypasses this entirely by routing straight to the container's IPv4 socket — masking the problem. Fixed by using `127.0.0.1` explicitly in the healthcheck instead of `localhost`.

**Result:** Container reports `healthy` consistently. This is a textbook "Running ≠ Ready" story (plan section 52 literally calls this out) — the app was never actually broken, only the *health signal* was lying, which is arguably worse in production (a rolling deployment or Kubernetes readiness gate would have blocked healthy traffic).

**Answers:** ¿Qué diferencia hay entre readiness y liveness? · ¿Cómo investigar un problema post-deploy que las métricas no explican de forma obvia? · Running no significa Ready (section 52 principle, verified hands-on).

---

## Sprint 5 (bonus) — A stale process from three sprints ago shadowed the real bug

**Situation:** After fixing the nginx healthcheck, `GET /api/movies` through the nginx proxy still returned `500` with a body shaped like an Express/Node proxy error (`text/plain`, `Vary: Origin`) — not our API's `ProblemDetails` JSON.

**Task:** Figure out why the response didn't match either nginx's error format or our app's.

**Action:** Checked `netstat`/`Get-NetTCPConnection` on the host for port 4200 and found **two** listeners: the Docker container (`::`, all interfaces) and a leftover Node.js `ng serve` process from Sprint 3's manual testing, bound to `::1` only. On Windows, `::1` (IPv6 loopback) took precedence over `::` for `localhost` resolution, so every request was silently served by the zombie dev server — which proxied `/api` to a `dotnet run` instance that no longer existed, producing exactly that generic 500.

**Result:** Killed the stale process; the real containerized stack answered correctly. Lesson: "container is healthy" is not sufficient evidence that *your test request* reached that container — always verify what's actually listening on the port you're hitting before debugging the app itself.

**Answers:** Troubleshooting general de "funciona en un lado y no en otro" — buena anécdota de proceso de diagnóstico, no de una herramienta específica.

---

## Sprint 6 — Reading a third-party GitHub Action's actual release tags

**Situation:** First real run of the CI pipeline on GitHub Actions (PR #1). Backend and frontend jobs passed fully (build, 8/8 unit tests, 3/3 integration tests) — but both failed on the last step.

**Task:** Diagnose a fast, late-stage-only failure (Quality Gate is designed to only reject *after* the expensive steps already ran clean, which is unusual — worth double-checking whether Fail Fast ordering was actually followed).

**Action:** Log showed `##[error]Unable to resolve action 'aquasecurity/trivy-action@0.28.0', unable to find version '0.28.0'`. Checked the action's actual repository tags via `gh api repos/aquasecurity/trivy-action/tags` — releases are tagged `v0.28.0`, `v0.36.0`, etc. (with a `v` prefix), not bare semver. Fixed the ref and re-ran.

**Result:** All 7 checks green (CodeQL ×2, Backend CI, Frontend CI, Docker Build ×2, Quality Gate) on the second run. Confirmed via logs that the PR's Docker build correctly ran with `push: false` — validating the Immutable Artifact / build-on-every-PR-but-push-only-on-main design actually behaves as intended, not just in theory.

**Answers:** ¿Qué es un Quality Gate? · ¿Cómo diseñar un pipeline seguro? · Build Once, Deploy Many (el tagging por SHA ya está probado, la promoción real llega en el Sprint 8).

---

## Sprint 7 — AKS rejects its own default network config

**Situation:** First real `terraform apply` against Azure (dev environment): resource group, VNet/subnet, Log Analytics, ACR, Key Vault + secret, and Postgres Flexible Server all created successfully (~7 minutes). Then `azurerm_kubernetes_cluster.main` failed.

**Task:** Diagnose a `400 Bad Request` from the Azure API on cluster creation, without burning more time (and cost) on repeated failed applies.

**Action:** Error: `ServiceCidrOverlapExistingSubnetsCidr` — "the specified service CIDR 10.0.0.0/16 is conflicted with an existing subnet CIDR 10.0.1.0/24." Root cause: the `network_profile` block didn't set `service_cidr` explicitly, so AKS defaulted to `10.0.0.0/16` for its internal Kubernetes Service IPs — which is exactly the VNet's own address space (also `10.0.0.0/16`, containing the `10.0.1.0/24` node subnet). Two independent IP address plans (the VNet's and AKS's internal services) collided because one was implicit. Fixed by setting `service_cidr = "172.16.0.0/16"` and `dns_service_ip = "172.16.0.10"` — a range guaranteed not to overlap the VNet.

**Result:** Since Postgres/ACR/Key Vault/network were already applied and safely recorded in state, the fix only needed to `plan`/`apply` the 2 missing AKS resources — Terraform didn't touch anything already created. Cluster came up in ~5 minutes; validated for real by pushing a backend image to the real ACR and running a pod on the real AKS node that pulled it with **zero `imagePullSecrets`**, proving the `AcrPull` role assignment (also Terraform-managed) actually works end-to-end.

**Answers:** ¿Por qué Terraform? (el state parcial es justamente lo que evita rehacer todo por un solo recurso fallido) · ¿Cómo organizar módulos Terraform? · Tema de Kubernetes networking (CIDR planning, IPAM) que rara vez se toca hasta que falla en producción.

---

## Sprint 8 — designing "Build Once, Deploy Many" so it's actually true, not just a tag

**Situation:** `ci.yml` (Sprint 6) already builds and tags an image once, pushing to GHCR. Sprint 8 needed to actually *deploy* that image — but the deployment target is AKS + ACR (Sprint 7, Azure), a different registry than CI uses.

**Task:** Deploy the exact bits CI tested, not a re-pull, re-tag, or (worse) a rebuild against the target environment — because a rebuild is precisely the "build once, deploy many" violation the pattern exists to prevent (a rebuild could pick up a dependency update between CI and deploy and silently ship something never tested).

**Action:** `deploy.yml` uses `az acr import --source ghcr.io/.../movieops-api:<sha-tag>` — a server-side registry-to-registry copy. No `docker pull`/`docker push`, no local Docker daemon involved in the CD runner at all; Azure copies the manifest and layers directly between registries. The image's digest travels unchanged from GHCR to ACR.

**Result:** The same artifact that passed `ci.yml`'s tests is what runs in every environment — provably, since the digest never changes across the copy. (Not yet run live — see the note in `docs/pipelines/PIPELINE_PATTERNS.md` about batching Sprint 8+9 validation together.)

**Answers:** ¿Qué significa Build Once, Deploy Many? · ¿Cómo versionar imágenes Docker? · ¿Qué diferencia hay entre CI y CD? (CI never talks to Azure at all; CD is the only thing that does)

---

## Design decisions worth their own STAR (no bug, but interview-worthy)

These didn't come from a failure — they're judgment calls made deliberately, which interviewers value just as much as debugging stories.

### Azure-first, no multi-cloud abstraction yet ([ADR-0001](adr/0001-cloud-provider-azure-first.md))
**Situation:** Plan requires Azure now, AWS later. **Task:** avoid rework when AWS lands. **Action:** organized Terraform by provider folder (`modules/azure/`, `modules/aws/` reserved empty) instead of writing `if var.cloud_provider == "azure"` conditionals. **Result:** zero coupling between providers; AWS becomes a parallel implementation, not a refactor. **Answers:** ¿Cómo organizar módulos Terraform? · ¿Cómo manejar ambientes?

### Observability built portable, not on Azure Monitor ([ADR-0002](adr/0002-observability-stack-portability.md))
**Situation:** Same Azure→AWS trajectory. **Task:** avoid observability work that doesn't survive a cloud migration. **Action:** committed to OpenTelemetry + self-hosted Prometheus/Grafana instead of the native Azure service. **Result:** the same Helm chart will run on AKS or EKS unchanged. **Answers:** ¿Cómo monitorear latencia y error rate? · ¿Qué es Shift Left / portability as a design constraint?

### One `PATCH .../collection` endpoint instead of three
**Situation:** Plan section 4 lists "cambiar estado", "calificar", "comentar" as three separate operations. **Task:** decide the API shape. **Action:** merged them into one partial-update endpoint over the same small entity instead of three near-identical endpoints. **Result:** less surface area, same functionality — a deliberate anti-over-engineering call. **Answers:** general judgment/tradeoff question, good for "tell me about a time you simplified a design."

---

## Cross-reference: plan questions already covered

From [section 54](../MovieOps_DevOps_Plan.md):

- ¿Qué diferencia hay entre CI y CD? → Sprint 4 entry, Sprint 6 (ci.yml vs. future cd-*.yml)
- ¿Qué es Pipeline as Code? / Fail Fast? / Fan-Out-Fan-In? / Quality Gate? → Sprint 6 entries + `docs/pipelines/PIPELINE_PATTERNS.md`
- ¿Cómo versionar imágenes Docker? / Build Once Deploy Many? → Sprint 6 (SHA tagging)
- ¿Cómo manejar secretos? → `.env` / `.gitignore` discipline (Sprint 0), `Tmdb__ApiKey` never committed (Sprint 3)
- ¿Qué diferencia hay entre readiness y liveness? → Sprint 5 entry (the nginx IPv6 bug)
- ¿Cómo hacer resiliente una integración externa? → Sprint 3 entry
- ¿Por qué Terraform? / ¿Cómo organizar módulos? → ADR-0001 + Sprint 7 entry (real apply, real bug, real fix)
- ¿Qué diferencia hay entre `plan` y `apply`? → Sprint 7: the plan showed 17 resources; after the AKS failure, the next plan showed only the 2 still missing — state is what makes that possible
- ¿Cómo manejar secretos? (ampliado) → Sprint 7: generated Postgres password never touched `.tfvars`/CLI history, went straight into `random_password` → Key Vault

Still open (will fill in as we build): rolling/blue-green/canary, GitOps/drift/reconciliation, Argo Rollouts, full incident-simulation set (Sprint 13).
