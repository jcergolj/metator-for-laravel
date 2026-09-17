# Make unchanged provisioning reruns verified no-ops

When existing resources match the selected site configuration, provisioning verifies them and reports them as unchanged without rewriting configuration, upgrading packages, reloading services, restarting workers, or replacing scheduler entries, including for the target site. Credentials, keys, environment values, and data remain intact. Supported site-owned differences are reconciled under the existing ownership and shared-infrastructure rules; failed readiness checks must be reported rather than concealed by a successful no-op summary.
