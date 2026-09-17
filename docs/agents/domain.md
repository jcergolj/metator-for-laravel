# Domain documentation

Metator is a single-context repository.

## Read before working

1. [CONTEXT.md](../../CONTEXT.md): the project's glossary and scope description.
2. Relevant decisions in [docs/adr/](../adr/): read the decisions affecting the area being changed.
3. [V1 acceptance requirements](../v1-acceptance.md): the fresh-server, fifth-site, no-op, recovery, and operational-isolation release gate.
4. The target GitHub issue, its comments, and its blocking dependencies.

If a domain document is absent, continue without inventing its contents. Create glossary entries and decisions when they are actually resolved, not as speculative scaffolding.

## Use the domain language

Use **site**, **site ID**, and **operational isolation** as defined in the glossary. A repository is not a site: multiple sites can share one repository. Operational isolation does not promise containment of a compromised application runtime.

Keep the glossary focused on terminology. Put architectural trade-offs in ADRs and implementation acceptance criteria in issues. Update resolved terminology promptly when using the domain-modeling workflow.

## Respect decisions and verify implementation

The ADRs describe the agreed design; they are not proof that the current code implements it. Inspect actual commands, generated scripts, templates, and tests before making claims about current behavior.

Surface conflicts with relevant ADRs explicitly instead of silently overriding them. Keep Metator's provisioning responsibility separate from Deployer's release lifecycle, and do not expand v1 into general OS/security hardening.

The acceptance document records requirements, not passing results. Report what was actually verified, distinguishing mocked behavior from real Ubuntu service and deployment tests.
