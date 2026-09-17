# Metator v1 release gate

Metator v1 is ready only when automated acceptance tests on disposable Ubuntu 24.04 VPSs or VMs demonstrate the scenarios below. Existing shell tests supplement these tests; they do not substitute for real service and deployment integration. These are agreed requirements, not a record of passing results.

The supported baseline includes PHP 8.4 and 8.5 side by side, with PHP 8.5 the default for new sites, SQLite or local MariaDB, Caddy-managed public HTTPS, optional Redis, and the selected worker and scheduler capabilities. Basic OS hardening and operator SSH access are external prerequisites. Operational isolation, rather than containment of a compromised runtime, is the guarantee under test.

## 1. Fresh server to first working site

- Run local setup, explicit shared-infrastructure preparation, and site provisioning through Artisan.
- Verify infrastructure readiness, accurate streamed output, and successful exit status.
- Invoke Deployer separately, as the operator would; provisioning must not deploy code automatically.
- Verify HTTP serving, database access, scheduler execution when selected, and job processing when workers are selected.
- Exercise the supported database and worker choices across the acceptance suite.

## 2. Four running sites to a fifth site

- Keep four sites serving requests and processing their configured work while provisioning and separately deploying a fifth.
- Include two sites using the same repository and sites using different supported PHP minor versions.
- Verify existing site configuration, credentials, keys, data, and running work remain unaffected.
- Verify compatible shared infrastructure is reused without package changes or unrelated worker restarts.
- Verify any necessary graceful Caddy reload leaves existing sites available.

## 3. Unchanged rerun

- Rerun provisioning with matching configuration and resources.
- Verify no configuration rewrites, credential or key rotation, service actions, or duplicate managed entries.
- Verify resources are reported as unchanged and readiness failures are not reported as success.

## 4. Failure and retry

- Inject database, Git access, Caddy configuration or activation, and Supervisor failures.
- Verify nonzero exit status, accurate local failure output, and no false readiness report.
- Verify existing sites remain operational and configuration changed by failed activation is restored.
- Preserve successfully created site-owned resources and verify reruns recover without deleting data, rotating credentials, or duplicating configuration.

## 5. Site-scoped operations

- Clear one site's Redis cache and verify another site's cache remains intact.
- Verify cache clearing also preserves the target site's separate queue, Horizon, and Redis-backed session state.
- Restart or activate one site's workers and verify other sites' workers are unaffected.

## Evidence required for release

Record the tested Ubuntu image, PHP and shared-service versions, representative Laravel applications, executed commands, and test results. A passing bootstrap summary alone is insufficient: both the first-site deployment handoff and the existing-server add-site scenario must pass.
