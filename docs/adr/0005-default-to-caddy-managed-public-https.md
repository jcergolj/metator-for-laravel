# Default to Caddy-managed public HTTPS

Metator provisions site-specific Caddy configuration while Caddy obtains and renews public HTTPS certificates; the operator supplies the domain and points DNS at the VPS, with Cloudflare DNS automation remaining optional. Metator rejects a domain assigned to another site and validates the complete candidate Caddy configuration before activation through a graceful reload. This removes the existing dependency on a fixed shared Cloudflare certificate pair and leaves certificate lifecycle management with Caddy.
