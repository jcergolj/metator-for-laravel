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
                $this->archiveScripts($scriptsPath, $archive);
            } else {
                $staging = sys_get_temp_dir().'/metator-staging-'.bin2hex(random_bytes(8));
                $this->files->copyDirectory($scriptsPath, $staging);
                $this->files->copy($environmentInput, $staging.'/.env-input');
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
                'set -eu; sudo rm -rf %s; sudo install -d -m 755 %s; sudo tar -xzf %s -C %s; sudo rm -f %s; sudo env METATOR_OPERATION=%s bash %s/server-bootstrap.sh',
                ...array_map('escapeshellarg', [
                    $remotePath,
                    $remotePath,
                    $remoteArchive,
                    $remotePath,
                    $remoteArchive,
                    $operation,
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
