# Metator

Metator prepares an already basically secured Ubuntu VPS for hosting Laravel sites before their deployment with Deployer.

## Language

**Site**:
An independently provisioned deployment target for a Laravel application. Multiple sites may use the same Git repository while retaining their own configuration, data, and running work.
_Avoid_: Repository as a synonym for site

**Site ID**:
The immutable, server-unique identifier of a site, independent of its repository, domain, or local checkout name.
_Avoid_: Repository name as site identity

**Operational isolation**:
The guarantee that provisioning or operating one site does not unintentionally change or interrupt another site's configuration, data, or running work. Sites share a trusted operator; containment of a compromised application's runtime is not part of this guarantee.
_Avoid_: Isolation without qualification, tenant isolation
