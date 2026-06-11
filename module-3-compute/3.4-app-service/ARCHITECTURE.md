# Architecture Notes: Lab 3.4 — App Service

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| App Service Plan SKU | Premium V4 P0V4 (1 vCPU, 1.75 GB RAM, auto-scaling enabled) | B1 Basic (~€11/mo, no slots), S1 Standard (~€60/mo, simpler), P1v3 (~€115/mo, higher performance) | P0V4 (~€115/mo) is costly for a lab but includes Deployment Slots and VNet Integration. Lab justifies the cost by teaching advanced features; production chooses B1 for simple blogs, S1 for scaling needs, P1+ for demanding apps. |
| Runtime Stack | Node 20 LTS (Linux) | Python 3.9+, .NET 6, Java 11, Go | Node.js is lightweight and familiar to many students; Linux keeps costs lower and aligns with the game server theme. Production chooses based on team expertise and app requirements. |
| OS | Linux | Windows | Linux App Service is slightly cheaper and aligns with the SkyCraft narrative (Ubuntu VMs in earlier labs). Windows is required for ASP.NET or IIS-dependent apps. |
| Deployment Slots | One staging slot | No slots, or multiple (e.g., staging + canary) | Single staging slot teaches blue-green deployments without overcomplicating cost. Production may add canary or QA slots. |
| Auto-Scaling Rules | CPU > 70% scale out (+1 instance), CPU < 30% scale in (−1 instance), 1–3 replicas | No auto-scaling, fixed 3 instances, or aggressive rules (threshold 50%) | These rules are conservative and teach auto-scaling fundamentals. Production tuning depends on application metrics (request count, custom telemetry). |
| VNet Integration | Configured but no backend services connected | Full hub-spoke with private access to DB/cache | Lab shows the configuration without using it; production uses it to reach private databases or in-VNet APIs securely. |
| HTTPS/TLS | Required (httpsOnly: true) | Optional | Enforces security by default. Production always enables this. |
| System-Assigned Managed Identity | Enabled on the Web App | None, or User-Assigned for multi-app scenarios | Simplifies secret retrieval (e.g., from Key Vault) without storing credentials in app config. |
| Connection Draining | Not explicitly configured | Enabled on load balancer rules | Graceful shutdown is important; production sets connection drain timeout on any front-facing LB. |
| Backups | Not configured | Automated daily/weekly backups with retention | Lab relies on stateless app design (no persistent data); production backs up app content and database separately. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Application Code | Empty/default Node app | Real dashboard or monitoring service | Lab deploys a placeholder; production integrates with logging, dashboards, and authentication systems. |
| Deployment | Manual slot swap or FTP | Automated CI/CD (Azure DevOps, GitHub Actions) | Lab teaches slot mechanics; production automates build, test, and release. |
| Custom Domain | Azure-assigned domain (e.g., dev-skycraft-swc-app01.azurewebsites.net) | Custom domain + SSL certificate (Let's Encrypt, managed cert) | Lab uses the default; production uses branded domains and auto-renewing certs. |
| Authentication | None (public access) | Azure AD / Entra ID, or OAuth 2.0 | Lab exposes the app publicly; production protects it behind identity verification. |
| Monitoring & Alerting | Minimal (auto-scale rules only) | Application Insights, Log Analytics, custom alerts | Lab doesn't collect app logs or metrics; production exports performance and error data. |
| Database Connectivity | VNet Integration configured but no backend | Private endpoint to Azure SQL or CosmosDB | Lab shows the config; production uses it to reach a secure database in the spoke VNet. |
| Cost Optimization | No cost controls (runs 24/7 on P0V4) | Scheduled scale-down, spot instances, right-sizing | P0V4 is expensive; production may downsize to S1 or add auto-shutdown for non-prod. |
| CDN / Caching | No caching or CDN | Azure Front Door or CDN for static assets | Lab serves everything from a single region; production caches CSS/JS globally. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Operational Excellence (managed platform, slots enable safe deployments)
- **Cost Management:** P0V4 is the "learning tax"; production downsizes to S1 or B1. Auto-scaling is enabled but conservative; production tunes thresholds based on load testing.
- **Reliability:** Deployment slots teach safe deployments without downtime. Auto-scaling to 3 instances provides redundancy. VNet Integration enables private access to backend services.
- **Security:** System-managed identity enables secret retrieval; HTTPS-only enforces encrypted transit. Production adds Azure AD authentication and DDoS protection (Azure Front Door).
- **Performance:** Auto-scaling on CPU metric is basic; production adds custom metrics (request count, custom business logic).

## 4. Cost / FinOps note

**Monthly recurring cost (if left on 24/7)**:
- App Service Plan P0V4 (1 instance): ~€115/mo
- Staging slot (charged as another instance if running): ~€115/mo (unless you deallocate it to save cost)
- Auto-scale to 3 instances (if sustained under high load): ~€345/mo total
- **Estimated typical cost**: €115–230/mo (production slot + occasional scaling).

**Lab cost controls**:
- **Deallocate the staging slot when not testing** (frees ~€115/mo). Slots still exist but don't consume compute.
- Use auto-shutdown policy if available (though App Service doesn't natively support auto-shutdown like VMs do); could switch to B1 (~€11/mo) after learning.
- Monitor scaling events; if the app never scales, downsize the plan to S1 (~€60/mo).

**Cleanup reminder after the lab**:
- **Delete the App Service Plan** (frees all associated costs). Deleting the web app without the plan leaves the plan running and billing.
- **Delete the staging slot first**, then the web app, then the plan (dependencies matter).
- **Delete VNet Integration rule** if no backend services depend on it (no direct cost but keeps the config clean).
- Exported logs in Log Analytics continue to incur ingestion + retention charges; delete old workspaces or set retention to 30 days.
