# Leave the first code deployment to the operator

Metator stops at verified site-infrastructure readiness and prints the exact next Deployer command; it neither runs the first deployment automatically nor claims the application is live. The operator runs Deployer separately afterward, and Deployer owns release deployment and site-scoped worker activation. End-to-end v1 acceptance must still exercise provisioning followed by deployment on both a fresh server and a server with existing sites, since provisioning success alone does not establish that the handoff works.
