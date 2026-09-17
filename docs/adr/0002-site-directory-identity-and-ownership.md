# Site directories follow site identity and require known ownership

Each site has a unique directory under `/var/www`, such as `/var/www/site-1` and `/var/www/site-2`, even when both sites use the same repository. Metator may reuse an existing site directory only when its ownership record identifies the requested site; missing or conflicting ownership stops provisioning without modifying the directory, regardless of whether the repository matches. This permits predictable reruns while deliberately foregoing automatic adoption of unmanaged directories in v1.
