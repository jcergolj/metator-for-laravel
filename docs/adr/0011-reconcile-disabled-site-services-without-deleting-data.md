# Reconcile disabled site workers and scheduler without deleting data

Provisioning reconciles disabled worker and scheduler capabilities by stopping and removing only the site's managed worker configuration and removing only its managed scheduler entry. Databases, Redis data, credentials, application files, and shared services are preserved. Database-engine changes and other data migrations are rejected with an explanation rather than attempted during ordinary provisioning, keeping capability changes meaningful without turning reconciliation into destructive removal or migration.
