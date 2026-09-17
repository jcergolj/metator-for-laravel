# Limit v1 database provisioning to SQLite and local MariaDB

Metator v1 offers SQLite with a site-owned database file under the site's shared directory, preserved across deployments and reruns, or a shared local MariaDB service with a separate database, user, and credentials per site. The provisioning option is named MariaDB while Laravel uses its `mysql` connection driver. External database servers, Oracle MySQL installation, and database-engine migrations are outside the initial supported workflow, keeping provisioning and ownership behavior bounded and testable.
