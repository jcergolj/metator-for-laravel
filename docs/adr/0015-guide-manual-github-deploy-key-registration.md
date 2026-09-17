# Guide manual GitHub deploy-key registration from Artisan

Metator generates a separate deploy key on the VPS for each site, including sites that share a repository, and Artisan displays its public key and the repository's deploy-key settings URL. The operator registers the key as read-only, then Metator verifies repository access from the VPS before proceeding; reruns preserve the key, test access first, and repeat registration guidance when needed. This keeps v1 independent of GitHub API credentials while providing a guided, verifiable setup rather than an undocumented manual step.
