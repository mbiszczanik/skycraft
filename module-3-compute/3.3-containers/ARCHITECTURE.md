# Architecture Notes: Lab 3.3 — Containers

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| ACR SKU | Standard | Basic (~€4.20/mo, minimal storage), Premium (~€420/mo, geo-replication, private endpoints) | Standard (~€20/mo) is the "learning tier": enough storage for a few images, no complex features, not so expensive it stalls learning. Production chooses based on image volume and replication needs. |
| ACR Authentication | Admin User enabled (username/password) | RBAC + Managed Identity, Service Principal | Admin user is simple to teach; production disables admin user and uses RBAC or service principals to avoid shared credentials. |
| Container Instances (ACI) | 1 CPU, 1 GB memory, public IP, TCP port 80 | 0.5 CPU / 0.5 GB (lighter, slower), 2+ CPU (heavier, costlier) | 1 CPU / 1 GB is the default "hello world" size; enough to run a simple auth service. Production right-sizes based on profiling (often smaller). Public IP teaches external access; production uses private endpoints. |
| Container Apps (ACA) | 0.25 CPU, 0.5 GB memory, 1–3 replicas, HTTP concurrency scaling | Dedicated compute (App Service), serverless (Functions) | Container Apps auto-scales on HTTP traffic; this teaches "serverless thinking" while keeping containers simple. Production chooses App Service for stateful apps, Functions for event-driven, or ACA for stateless microservices. |
| Image Source | ACR (private registry) | Docker Hub (public), Azure Container Registry with custom builds | Private ACR teaches proprietary image management; pulling from hub would require extra steps (az acr build). Lab assumes images are pre-built or built manually; production automates via ACR Tasks or CI/CD pipelines. |
| Container Registry Credentials | Hardcoded in Bicep (listCredentials() function) | TODO(author): Explain why credentials are safe here | This approach exposes the registry password in template outputs; production uses Managed Identity and Key Vault to avoid storing credentials in code. |
| Ingress | External (public FQDN) for both ACI and ACA | Private endpoints + API Gateway | Public ingress teaches direct container access; production places containers behind a firewall or API gateway to control traffic. |
| Monitoring | Logging to Azure Monitor (Container Apps only) | Application Insights, custom logging | ACA sends logs to Monitor by default; ACI has no explicit logging. Production exports logs to Log Analytics for querying and alerting. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Image Management | Assumes images exist or are built manually | Automated CI/CD pipeline (ACR Tasks, GitHub Actions) | Lab expects users to run `az acr build` manually; production auto-builds on git push. |
| Secrets Management | Registry credentials in template outputs | Stored in Key Vault, fetched at deploy time | Listing credentials in outputs exposes them in the deployment history. Production uses Key Vault references (identityRef). |
| Scaling | ACA: static rules (1–3 replicas, HTTP concurrency) | Dynamic scaling based on custom metrics (CPU, queue depth, custom telemetry) | Lab scaling is basic; production adds Kafka/Service Bus triggers, custom KEDA scaler rules. |
| VNet Integration | ACI: public IP only; ACA: no explicit VNet binding | Private endpoints, VNet integration, network policies | Lab containers are internet-exposed; production keeps them private and routes through API Gateway or Ingress Controller. |
| Persistence | No volumes or state storage | Persistent volumes (Azure Files, Blob), stateless design | Lab containers are ephemeral; production uses volumes for databases or caches, or redesigns to be truly stateless. |
| Security | Admin user enabled, public images | RBAC, Managed Identity, image signing, vulnerability scanning | Lab trusts all images; production scans for vulnerabilities (Trivy, Aqua) and signs images (Notary). |
| Cost Optimization | Always-on instances | Spot instances, scheduled scale-down, multi-tenancy | Lab runs 24/7; production uses auto-shutdown for non-production environments. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Operational Excellence (containers teach immutability and reproducibility)
- **Cost Management:** ACR Standard (~€20/mo) is reasonable for learning; ACI at 1 CPU (~€30/mo on-demand) and ACA at 0.25 CPU (~€7.50/mo on-demand) show cost differences. Auto-scale on ACA demonstrates efficient resource use.
- **Security:** ACR SKU and admin user model expose security decisions; switching to RBAC teaches least privilege.
- **Reliability:** Multiple replicas (1–3) in ACA teach redundancy without the complexity of Kubernetes.
- **Performance:** Container-native scaling on HTTP metrics (concurrency) is simpler than VM CPU-based scaling.

## 4. Cost / FinOps note

**Monthly recurring cost (if left on 24/7)**:
- ACR Standard: ~€20/mo (shared across all labs if reused)
- ACI (1 CPU, 1 GB, always-on): ~€30/mo compute + storage for image pulls
- ACA (0.25 CPU, 0.5 GB, 1–3 replicas, average 2): ~€15/mo compute + ~€20/mo Container Apps Environment
- **Estimated total**: €85/mo with both ACI and ACA running.

**Lab cost controls**:
- Deploy ACI **or** ACA, not both, to halve the cost.
- Use spot instances (if available for containers) for further savings.
- Delete images from ACR after the lab to avoid indefinite storage charges.

**Cleanup reminder after the lab**:
- **Delete Container App Environment** (frees ~€20/mo even if apps are idle).
- **Delete ACI instance** (frees ~€30/mo).
- **Delete ACR or clear all images** (frees at least storage costs; ACR registry itself is ~€20/mo).
- Images in ACR storage cost additional per GB (~€0.02/GB/mo); large images left in ACR add up.
- Orphaned Container Apps Environments with no apps still incur charges; delete these immediately.
