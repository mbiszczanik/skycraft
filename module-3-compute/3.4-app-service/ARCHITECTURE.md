# Architecture Notes: Lab 3.4 — App Service

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| App Service Plan SKU | Premium V4 P0V4 (one instance, autoscale up to three) | B1 Basic (no slots, no autoscale), S1 Standard (slots and autoscale), P0V3 (previous Premium generation) | The lab needs deployment slots and autoscale, which Basic lacks; S1 and P0V4 both have them. P0V4 is chosen for its hardware (Premium V4: faster processors, NVMe local storage), not its price: on Linux in Sweden Central P0V4 costs 0.0949 USD/h and S1 0.095 USD/h (Azure Retail Prices API, read 2026-10-08; current prices on the [App Service pricing page](https://azure.microsoft.com/pricing/details/app-service/linux/)). VNet integration is not the reason either: Basic has it. Production chooses B1 for simple sites, S1 or P0V4 when it needs slots and autoscale, larger Premium sizes for demanding apps. |
| Runtime Stack | Node 22 LTS (Linux), startup command `pm2 serve /home/site/wwwroot --no-daemon` | Node 24 LTS, Python, .NET, Java, or a static site host | Node.js is lightweight and familiar to many students; Linux keeps costs lower and aligns with the game server theme. Node 20 LTS is no longer offered (Portal, 2026-10-15). The dashboard is one static `index.html`, which a Node runtime does not serve by itself: `pm2 serve` (PM2 is in the App Service Node images) serves `/home/site/wwwroot` as a static site. Production chooses based on team expertise and app requirements. |
| OS | Linux | Windows | Linux App Service is slightly cheaper and aligns with the SkyCraft narrative (Ubuntu VMs in earlier labs). Windows is required for ASP.NET or IIS-dependent apps. |
| Deployment Slots | One staging slot | No slots, or multiple (e.g., staging + canary) | Single staging slot teaches blue-green deployments without overcomplicating cost. Production may add canary or QA slots. |
| Auto-Scaling Rules | CPU > 70% scale out (+1 instance), CPU < 30% scale in (−1 instance), 1–3 replicas | No auto-scaling, fixed 3 instances, or aggressive rules (threshold 50%) | These rules are conservative and teach auto-scaling fundamentals. Production tuning depends on application metrics (request count, custom telemetry). |
| VNet Integration | On the app and on the staging slot (integration is a slot setting: neither cloned nor swapped), route all; no backend services connected | Full hub-spoke with private access to DB/cache | Lab shows the configuration without using it; production uses it to reach private databases or in-VNet APIs securely. |
| HTTPS/TLS | Required (httpsOnly: true) | Optional | Enforces security by default. Production always enables this. |
| System-Assigned Managed Identity | Not enabled | System-assigned, or User-Assigned for multi-app scenarios | The dashboard reads no secrets, and the Portal path creates the app without an identity, so the Bicep does not add one either (same end state on both paths). Production enables one as soon as the app reads secrets (e.g., from Key Vault), instead of storing credentials in app config. |
| Connection Draining | Not explicitly configured | Enabled on load balancer rules | Graceful shutdown is important; production sets connection drain timeout on any front-facing LB. |
| Backups | Automatic backups only: hourly, kept 30 days, built into Basic and above at no extra cost (guide step 3.4.13 reviews them); no custom backup | Custom backups to a storage account on a schedule, longer retention | Lab relies on stateless app design (no persistent data) and avoids a storage account the cleanup would have to remove; production adds custom backups when it needs downloadable copies or longer retention, and backs up databases separately. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Application Code | One static `index.html`, served by `pm2 serve` | Real dashboard or monitoring service | Lab deploys a placeholder; production integrates with logging, dashboards, and authentication systems. |
| Deployment | Manual slot swap or FTP | Automated CI/CD (Azure DevOps, GitHub Actions) | Lab teaches slot mechanics; production automates build, test, and release. |
| Custom Domain | Azure-assigned secure unique default hostname (`dev-skycraft-swc-app01-<16 characters>.swedencentral-01.azurewebsites.net`; the slot gets its own) | Custom domain + SSL certificate (Let's Encrypt, managed cert) | Lab uses the default; production uses branded domains and auto-renewing certs. The unique hostname cannot be claimed by anyone else after the app is deleted, which prevents subdomain takeover of a dangling DNS record. |
| Authentication | None (public access) | Azure AD / Entra ID, or OAuth 2.0 | Lab exposes the app publicly; production protects it behind identity verification. |
| Monitoring & Alerting | Minimal (auto-scale rules only) | Application Insights, Log Analytics, custom alerts | Lab doesn't collect app logs or metrics; production exports performance and error data. |
| Database Connectivity | VNet Integration configured but no backend | Private endpoint to Azure SQL or CosmosDB | Lab shows the config; production uses it to reach a secure database in the spoke VNet. |
| Cost Optimization | No cost controls (runs 24/7 on P0V4 until the cleanup) | Scheduled scale-down, right-sizing, reservations | A plan bills by the hour whether the app is used or not; production right-sizes the plan and deletes non-production plans when they are idle. |
| CDN / Caching | No caching or CDN | Azure Front Door or CDN for static assets | Lab serves everything from a single region; production caches CSS/JS globally. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Operational Excellence (managed platform, slots enable safe deployments)
- **Cost Management:** P0V4 costs about the same as S1; the cost of the lab is the hours the plan exists, so the guide's Clean Up deletes it. Production picks B1 where slots and autoscale are not needed. Auto-scaling is enabled but conservative; production tunes thresholds based on load testing.
- **Reliability:** Deployment slots teach safe deployments without downtime. Auto-scaling to 3 instances provides redundancy. VNet Integration enables private access to backend services.
- **Security:** HTTPS-only with TLS 1.2 enforces encrypted transit, and the secure unique default hostname cannot be taken over after the app is deleted. Production adds a managed identity for secret retrieval, Azure AD authentication and DDoS protection (Azure Front Door).
- **Performance:** Auto-scaling on CPU metric is basic; production adds custom metrics (request count, custom business logic).

## 4. Cost / FinOps note

**Recurring cost (Linux pay-as-you-go, Sweden Central, Azure Retail Prices API read 2026-10-08; current prices on the [App Service pricing page](https://azure.microsoft.com/pricing/details/app-service/linux/))**:
- App Service Plan P0V4 (1 instance): 0.0949 USD/h, about 2.30 USD/day or 69 USD/month.
- Staging slot: no extra charge. Slots run on the plan's instances ([Set up staging environments](https://learn.microsoft.com/azure/app-service/deploy-staging-slots)).
- Auto-scale to 3 instances (if sustained under high load): three times the plan, about 6.90 USD/day.
- Automatic backups, VNet integration, the autoscale setting: no extra charge.
- For comparison: S1 0.095 USD/h, P0V3 0.089 USD/h on the same meters.

**Lab cost controls**:
- **Delete the plan when you finish** (the guide's Clean Up): a plan bills by the hour whether the app is used or not, and App Service has no auto-shutdown like VMs do. Stopping the app does not stop the plan's billing.
- Leave Application Insights off in the create wizard (guide step 3.4.2): it bills for the data it collects.
- Monitor scaling events; in a long-lived environment where slots and autoscale are not needed, B1 is the cheaper tier.

**Cleanup reminder after the lab**:
- **Delete the App Service Plan** (frees all associated costs). Deleting the web app without the plan leaves the plan running and billing.
- **Order matters** — **detach the VNet integration first** (the app *and* every slot) and confirm `AppServiceSubnet` no longer shows a service association link, then delete the web app (its slots go with it), then the autoscale setting, then the plan. `Remove-LabResource.ps1` does exactly this, and finds the autoscale setting through the plan it targets (the Portal names it `<plan>-Autoscale-<n>`); deleting the plan while it is still integrated leaves an orphaned service association link that blocks deleting the subnet, the VNet, their NSGs and the whole resource group.

## 5. Bicep implementation note (AVM)

- **Plan**: `avm/res/web/serverfarm` — Linux P0v4 with the lab-friction overrides `zoneRedundant: false` and `skuCapacity: 1`: the module defaults `zoneRedundant` to `true` for P and EP SKUs and `skuCapacity` to `3` for every SKU, and zone redundancy needs at least two workers, so a one-worker lab plan opts out of it (docs/bicep-standards.md §4.5).
- **App and slot**: `avm/res/web/site`, with the staging slot declared through the module's `slots` parameter. The slot inherits `siteConfig` (runtime `NODE|22-lts` and `appCommandLine: 'pm2 serve /home/site/wwwroot --no-daemon'`), `outboundVnetRouting` (route-all, the successor to the legacy `siteConfig.vnetRouteAllEnabled` flag), HTTPS-only **and the regional VNet integration** from the app. That is the swap-safe configuration, the Portal path reaches it by cloning the app's settings and connecting both slots (guide steps 3.4.5 and 3.4.10), and cleanup detaches both integrations. The explicit `siteConfig` object replaces the module's default one, so `ftpsState: 'FtpsOnly'` is restated in it (it would otherwise be dropped), while `alwaysOn` is left at Azure's default `false` — the slot inherits the same object. `autoGeneratedDomainNameLabelScope: 'TenantReuse'` gives the app the secure unique default hostname the Portal gives it; it can be set only when the app is created, so a redeploy over an app created by an earlier version of this template, without it, may be refused: run the cleanup first. No managed identity, as on the Portal path.
- **Autoscale**: a local fallback module (`modules/autoscale.bicep`), because `avm/res/insights/autoscale-setting` is only *Proposed* (docs/bicep-standards.md §4.3).
