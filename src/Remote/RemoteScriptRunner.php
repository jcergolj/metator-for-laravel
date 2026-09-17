<?php

declare(strict_types=1);

namespace Jcergolj\MetatorForLaravel\Remote;

use Illuminate\Filesystem\Filesystem;
use RuntimeException;

class RemoteScriptRunner
{
    public function __construct(
        protected Filesystem $files,
    ) {
    }

    /** @param array<string, mixed> $site */
    public function run(array $site, string $operation, string $scriptsPath, callable $output, ?string $environmentInput = null): int
    {
        $archive = tempnam(sys_get_temp_dir(), 'metator-');
        if ($archive === false) {
            throw new RuntimeException('Could not create a temporary script archive.');
        }
        $archive .= '.tar.gz';

        $staging = null;
        try {
            if ($environmentInput === null) {
                $staging = $this->stageScripts($scriptsPath, $site, $operation);
                $this->archiveScripts($staging ?? $scriptsPath, $archive);
            } else {
                $staging = sys_get_temp_dir().'/metator-staging-'.bin2hex(random_bytes(8));
                $this->files->copyDirectory($scriptsPath, $staging);
                $this->files->copy($environmentInput, $staging.'/.env-input');
                if ($operation === 'provision') {
                    $this->writeCloudflareSecrets($staging, $site);
                }
                $this->archiveScripts($staging, $archive);
            }
            $target = $site['ssh']['user'].'@'.$site['ssh']['host'];
            $remoteArchive = '/tmp/metator-'.$site['site_id'].'.tar.gz';
            $status = $this->execute(
                'scp -q -o BatchMode=yes '.escapeshellarg($archive).' '.escapeshellarg($target.':'.$remoteArchive),
                $output,
            );
            if ($status !== 0) {
                return $status;
            }

            $remotePath = '/var/init-scripts/metator/'.$site['site_id'];
            $remoteCommand = sprintf(
                'set -eu; sudo rm -rf %s; sudo install -d -m 755 %s; sudo tar -xzf %s -C %s; sudo rm -f %s; sudo env METATOR_OPERATION=%s CLIENT_PUBLIC_KEY=%s bash %s/server-bootstrap.sh',
                ...array_map('escapeshellarg', [
                    $remotePath,
                    $remotePath,
                    $remoteArchive,
                    $remotePath,
                    $remoteArchive,
                    $operation,
                    $this->clientPublicKey(),
                    $remotePath,
                ]),
            );

            return $this->execute(
                'ssh -o BatchMode=yes '.escapeshellarg($target).' '.escapeshellarg($remoteCommand),
                $output,
            );
        } finally {
            $this->files->delete($archive);
            if ($staging !== null) {
                $this->files->deleteDirectory($staging);
            }
        }
    }

    private function clientPublicKey(): string
    {
        $home = getenv('HOME') ?: '';
        $paths = glob($home.'/.ssh/*.pub') ?: [];
        usort($paths, static fn (string $left, string $right): int => str_starts_with($left, $home.'/.ssh/id_') ? -1 : (str_starts_with($right, $home.'/.ssh/id_') ? 1 : strcmp($left, $right)));
        foreach ($paths as $path) {
            if (is_file($path)) {
                $key = trim((string) file_get_contents($path));
                if (preg_match('/^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^ ]+)[[:space:]]+[^[:space:]]+/', $key) === 1) {
                    return $key;
                }
            }
        }

        throw new RuntimeException('No valid local public SSH key found in ~/.ssh.');
    }

    /** @param array<string, mixed> $site */
    private function stageScripts(string $scriptsPath, array $site, string $operation): ?string
    {
        if ($operation !== 'provision' || ! isset($site['cloudflare'])) {
            return null;
        }
        $staging = sys_get_temp_dir().'/metator-staging-'.bin2hex(random_bytes(8));
        $this->files->copyDirectory($scriptsPath, $staging);
        $this->writeCloudflareSecrets($staging, $site);

        return $staging;
    }

    /** @param array<string, mixed> $site */
    private function writeCloudflareSecrets(string $staging, array $site): void
    {
        if (! is_array($site['cloudflare'] ?? null)) {
            return;
        }
        $token = $site['cloudflare']['token'];
        $zoneId = $site['cloudflare']['zone_id'];
        $path = $staging.'/.cloudflare.env';
        $this->files->put($path, 'CF_TOKEN='.escapeshellarg($token).PHP_EOL.'CF_ZONE_ID='.escapeshellarg($zoneId).PHP_EOL);
        @chmod($path, 0600);
    }

    private function archiveScripts(string $scriptsPath, string $archive): void
    {
        if (! $this->files->isDirectory($scriptsPath) || ! $this->files->exists($scriptsPath.'/server-bootstrap.sh')) {
            throw new RuntimeException('Generated scripts are missing. Run metator:install first.');
        }

        $status = 0;
        exec('tar -C '.escapeshellarg($scriptsPath).' -czf '.escapeshellarg($archive).' .', result_code: $status);
        if ($status !== 0) {
            throw new RuntimeException('Could not archive the generated scripts.');
        }
    }

    private function execute(string $command, callable $output): int
    {
        $process = proc_open($command, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
        if (! is_resource($process)) {
            throw new RuntimeException('Could not start the remote command.');
        }

        foreach ([1, 2] as $stream) {
            stream_set_blocking($pipes[$stream], false);
        }
        while (! feof($pipes[1]) || ! feof($pipes[2])) {
            foreach ([1, 2] as $stream) {
                $chunk = fread($pipes[$stream], 8192);
                if ($chunk !== false && $chunk !== '') {
                    $output($chunk, $stream === 2);
                }
            }
            usleep(10000);
        }
        fclose($pipes[1]);
        fclose($pipes[2]);

        return proc_close($process);
    }
}
