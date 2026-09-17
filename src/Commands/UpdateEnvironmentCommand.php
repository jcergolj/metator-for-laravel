<?php

declare(strict_types=1);

namespace Jcergolj\MetatorForLaravel\Commands;

use RuntimeException;

class UpdateEnvironmentCommand extends RunRemoteProvisioningCommand
{
    protected $signature = 'metator:update-env {--config= : The site configuration file} {--input= : Local ignored dotenv input file}';

    protected $description = 'Explicitly update one site environment from a local ignored input file';

    public function handle(): int
    {
        try {
            $site = $this->loadSite();
            $input = $this->option('input');
            if (! is_string($input) || $input === '') {
                throw new RuntimeException('Choose a local ignored environment input with --input=.');
            }
            $path = $this->laravel->basePath($input);
            if (! is_file($path) || ! is_readable($path)) {
                throw new RuntimeException("Environment input was not found or is unreadable: {$path}");
            }
            $status = $this->runner->run(
                $site,
                'update-environment',
                $this->laravel->basePath('scripts'),
                function (string $chunk, bool $error): void {
                    $this->streamOutput($chunk, $error);
                },
                $path,
            );
        } catch (RuntimeException $exception) {
            $this->error($exception->getMessage());

            return self::FAILURE;
        }

        if ($status !== 0) {
            $this->error('Metator environment update failed. The previous environment was preserved when validation failed.');

            return self::FAILURE;
        }

        $this->info('Metator environment update finished. Refresh Laravel configuration and long-running workers through the application deployment lifecycle.');

        return self::SUCCESS;
    }
}
