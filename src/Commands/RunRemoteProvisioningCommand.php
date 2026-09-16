<?php

declare(strict_types=1);

namespace Jcergolj\MetatorForLaravel\Commands;

use Illuminate\Console\Command;
use Jcergolj\MetatorForLaravel\Remote\RemoteScriptRunner;
use RuntimeException;

class RunRemoteProvisioningCommand extends Command
{
    protected $signature = 'metator:provision {--config= : The site configuration file}';

    protected $description = 'Provision one selected site on its configured server';

    public function __construct(
        protected RemoteScriptRunner $runner,
    ) {
        parent::__construct();
    }

    public function handle(): int
    {
        return $this->runOperation('provision');
    }

    protected function runOperation(string $operation): int
    {
        try {
            $site = $this->loadSite();
            $status = $this->runner->run(
                $site,
                $operation,
                $this->laravel->basePath('scripts'),
                function (string $chunk, bool $error): void {
                    $this->{$error ? 'error' : 'line'}(rtrim($chunk, "\r\n"));
                },
            );
        } catch (RuntimeException $exception) {
            $this->error($exception->getMessage());

            return self::FAILURE;
        }

        if ($status !== 0) {
            $this->error("Metator {$operation} failed with exit status {$status}. Inspect the server before retrying.");

            return self::FAILURE;
        }

        $this->info("Metator {$operation} finished. No application deployment was run.");

        return self::SUCCESS;
    }

    /** @return array<string, mixed> */
    protected function loadSite(): array
    {
        $config = $this->option('config');
        if (! is_string($config) || $config === '') {
            throw new RuntimeException('Choose exactly one site configuration with --config=metator.production.php.');
        }
        $path = $this->laravel->basePath($config);
        if (! is_file($path)) {
            throw new RuntimeException("Site configuration was not found: {$path}");
        }
        $site = require $path;
        if (! is_array($site) || ! is_string($site['site_id'] ?? null) || ! is_array($site['ssh'] ?? null)
            || ! is_string($site['ssh']['user'] ?? null) || ! is_string($site['ssh']['host'] ?? null)) {
            throw new RuntimeException('Site configuration must define site_id and ssh.user/ssh.host.');
        }
        if (preg_match('/^[a-z](?:[a-z0-9]|-(?=[a-z0-9])){0,23}$/', $site['site_id']) !== 1
            || preg_match('/^[A-Za-z_][A-Za-z0-9_-]*$/', $site['ssh']['user']) !== 1
            || preg_match('/^[A-Za-z0-9.-]+$/', $site['ssh']['host']) !== 1) {
            throw new RuntimeException('Site ID or SSH target contains unsafe characters.');
        }

        return $site;
    }
}
