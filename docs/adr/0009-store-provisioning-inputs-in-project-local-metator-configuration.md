# Store provisioning inputs in a dedicated project-local configuration

Metator stores non-secret provisioning inputs in dedicated project-root PHP configuration files, such as `metator.production.php` and `metator.staging.php`, separate from Deployer's release configuration. Each file describes exactly one site: its identity, SSH target and provisioning user, domain, repository, PHP version, and selected capabilities; each provisioning invocation explicitly selects one file with `--config` and operates on that site only. The filename is a local label rather than site identity, and these files may be committed because passwords and tokens are kept outside them.

Paths and resource names are derived from the site ID. Artisan orchestrates remote scripts over SSH with streamed output and exit-status reporting, keeping questions local and remote provisioning noninteractive so saved inputs can support predictable retries.

`metator:install` performs local setup only: it collects site settings, writes the selected configuration file, generates minimal Deployer integration without overwriting an existing recipe, and prints the preparation, provisioning, and deployment commands. Remote mutations require explicit `metator:prepare-server` or `metator:provision` invocation; the operator runs Deployer separately afterward.
