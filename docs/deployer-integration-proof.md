# Deployer integration proof

## Local workflow evidence

The generated editable recipe uses Deployer 8.0.5 (the resolved version checked
for this proof) and reads the same site configuration used by Metator. A local
task-tree check loads the generated recipe with SQLite and each worker choice
(`none`, `queue`, and `horizon`) and verifies that the deploy workflow contains
runtime verification and release tasks, adds worker lifecycle hooks only when
workers are selected, and does not call Metator preparation or provisioning.
Run it with `php tests/test-deployer-workflow.php` after `composer install`.

The existing shell tests exercise failure propagation and stop-on-failure in
selected custom steps, and test provisioning input, ownership, and no-op
behavior. These are local tests; they do not establish remote service behavior.

## Upstream fit assessment

Inspection of Deployer v8.0.5's `recipe/provision.php` confirms its stock
provision group includes package updates/upgrades, SSH configuration, firewall,
and user changes. These conflict with Metator's explicit shared preparation,
operational-isolation, and existing-operator-access decisions (ADRs 0001,
0016, and 0018). The stock recipe is therefore not a suitable replacement for
Metator's site provisioning pipeline. The generated release recipe does use
Deployer for code deployment and lifecycle hooks, while Metator retains its
site-specific provisioning responsibilities.

## Evidence still required

No real Ubuntu 24.04 target was provisioned or deployed for this proof. There is
no real-service evidence for SSH/sudo, SQLite persistence, application release,
custom-step failure and remote retry, or recovery on an Ubuntu host. Ubuntu
26.04 is not currently listed as a supported baseline in ADR 0014 and is not
included in the v1 release gate. Do not infer support for it from local task
tree validation.

The local evidence confirms recipe loading and command composition, not that a
complete migration is worthwhile. Keep the existing custom provisioner for now:
stock provision behavior conflicts with current guarantees, and this proof has
not demonstrated a simpler compatible upstream alternative. Before issue #99
can close, add a disposable Ubuntu 24.04 end-to-end run and a final decision on
the bounded scope of any follow-up migration. Keep the Ubuntu 26.04 question
separate until the supported baseline is explicitly decided.
