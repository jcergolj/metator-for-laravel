<?php

namespace Jcergolj\MetatorForLaravel\Commands;

use Illuminate\Console\Command;
use Illuminate\Filesystem\Filesystem;
use function Laravel\Prompts\confirm;
use function Laravel\Prompts\select;
use function Laravel\Prompts\text;

class InstallDeployerScaffoldingCommand extends Command
{
    protected $signature = 'metator:install {--force : Overwrite existing files}';

    protected $description = 'Install Deployer deployment scaffolding into the current Laravel application';

    public function __construct(
        protected Filesystem $files,
    ) {
        parent::__construct();
    }

    public function handle(): int
    {
        $stubRoot = dirname(__DIR__, 2).'/stubs';
        $basePath = $this->laravel->basePath();
        $project = basename($basePath);
        $envExample = $stubRoot.'/.env.example';

        if (! $this->files->exists($envExample)) {
            throw new \RuntimeException("Missing .env.example stub: {$envExample}");
        }

        $placeholders = [
            '__APP_NAME__' => $project,
            '__DEPLOY_PATH__' => text(
                label: __('Application folder'),
                default: '/var/www/'.$project,
                required: true,
                validate: function (string $value): ?string {
                    return preg_match('#^/var/www/[A-Za-z0-9_.-]+$#', $value) !== 1
                        ? __('Application folder must be a simple path under /var/www.')
                        : null;
                },
            ),
            '__GITHUB_REPOSITORY__' => text(
                label: __('GitHub repository (owner/repository)'),
                default: 'jcergolj/'.$project,
                required: true,
                validate: function (string $value): ?string {
                    return preg_match('/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/', $value) !== 1
                        ? __('Repository must look like owner/repository.')
                        : null;
                },
            ),
            '__SERVER_IP__' => text(
                label: __('Server IP address'),
                required: true,
                validate: function (string $value): ?string {
                    return filter_var($value, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) === false
                        ? __('Enter a valid IPv4 address.')
                        : null;
                },
            ),
            '__GIT_DEPLOYER_NAME__' => text(
                label: __('Git SSH deployer name'),
                default: 'deployer-github-'.$project,
                required: true,
                validate: function (string $value): ?string {
                    return preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]*$/', $value) !== 1
                        ? __('Use only letters, numbers, dots, underscores, and hyphens.')
                        : null;
                },
            ),
            '__DOMAIN__' => text(
                label: __('Production domain'),
                required: true,
                validate: function (string $value): ?string {
                    return preg_match('/^[A-Za-z0-9.-]+$/', $value) !== 1
                        ? __('Enter a valid domain.')
                        : null;
                },
            ),
            '__DATABASE_DRIVER__' => select(
                label: __('Database driver'),
                options: [
                    'sqlite' => __('SQLite'),
                    'mysql' => __('MySQL'),
                ],
                default: 'sqlite',
            ),
            '__CONFIGURE_DEPLOY_USER_LOGIN__' => confirm(
                label: __('Configure SSH login for the deployer user?'),
                default: true,
            ) ? 'true' : 'false',
            '__USE_CLOUDFLARE__' => confirm(
                label: __('Include Cloudflare DNS configuration?'),
                default: false,
            ) ? 'true' : 'false',
            '__USE_SCHEDULER__' => confirm(
                label: __('Include the Laravel scheduler configuration?'),
                default: true,
            ) ? 'true' : 'false',
            '__USE_QUEUE__' => confirm(
                label: __('Include queue worker configuration?'),
                default: false,
            ) ? 'true' : 'false',
            '__USE_HORIZON__' => 'false',
        ];
        if ($placeholders['__USE_QUEUE__'] === 'true') {
            $placeholders['__USE_HORIZON__'] = confirm(
                label: __('Use Horizon to manage queued jobs?'),
                default: false,
            ) ? 'true' : 'false';
        }

        $targets = [
            'deploy.php.stub' => $basePath.'/deploy.php',
            'scripts/server-bootstrap.sh' => $basePath.'/scripts/server-bootstrap.sh',
            'scripts/lib/common.sh' => $basePath.'/scripts/lib/common.sh',
            'scripts/steps/01-prerequisites.sh' => $basePath.'/scripts/steps/01-prerequisites.sh',
            'scripts/steps/03-github-key.sh' => $basePath.'/scripts/steps/03-github-key.sh',
            'scripts/steps/04-shared-env.sh' => $basePath.'/scripts/steps/04-shared-env.sh',
            'scripts/steps/05-database.sh' => $basePath.'/scripts/steps/05-database.sh',
            'scripts/steps/06-permissions.sh' => $basePath.'/scripts/steps/06-permissions.sh',
            'scripts/steps/07-caddy.sh' => $basePath.'/scripts/steps/07-caddy.sh',
            'scripts/steps/10-deployer-instructions.sh' => $basePath.'/scripts/steps/10-deployer-instructions.sh',
        ];
        if ($placeholders['__CONFIGURE_DEPLOY_USER_LOGIN__'] === 'true') {
            $targets['scripts/steps/02-deployer-login.sh'] = $basePath.'/scripts/steps/02-deployer-login.sh';
        }
        if ($placeholders['__USE_CLOUDFLARE__'] === 'true') {
            $targets['scripts/steps/02-cloudflare.sh'] = $basePath.'/scripts/steps/02-cloudflare.sh';
        }
        if ($placeholders['__USE_SCHEDULER__'] === 'true') {
            $targets['scripts/steps/08-scheduler.sh'] = $basePath.'/scripts/steps/08-scheduler.sh';
        }
        if ($placeholders['__USE_QUEUE__'] === 'true') {
            $targets['scripts/steps/09-workers.sh'] = $basePath.'/scripts/steps/09-workers.sh';
        }

        foreach ($targets as $stub => $target) {
            $this->copyStub($stubRoot.'/'.$stub, $target, $placeholders);
        }
        $this->copyStub($envExample, $basePath.'/scripts/.env.example', $placeholders);

        $this->info('Metator scaffolding installed.');
        $this->line('Next steps:');
        $this->line('  1. Review deploy.php');
        $this->line('  2. Copy ./scripts to the server:');
        $this->line('     scp -r ./scripts root@your-server:/var/scripts/');
        $this->line('  3. Run the bootstrap script:');
        $this->line('     ssh root@your-server "chmod +x /var/scripts/server-bootstrap.sh && /var/scripts/server-bootstrap.sh"');

        return self::SUCCESS;
    }

    protected function copyStub(string $source, string $target, array $placeholders): void
    {
        if (! $this->files->exists($source)) {
            throw new \RuntimeException("Missing stub file: {$source}");
        }

        if ($this->files->exists($target) && ! $this->option('force')) {
            $this->warn("Skipped existing file: {$target}");

            return;
        }

        $this->files->ensureDirectoryExists(dirname($target));
        $contents = $this->files->get($source);
        $contents = $this->replacePlaceholders($contents, $placeholders);
        $this->files->put($target, $contents);

        if (str_ends_with($target, '.sh')) {
            @chmod($target, 0755);
        }

        $this->info("Installed: {$target}");
    }

    protected function replacePlaceholders(string $contents, array $placeholders): string
    {
        return str_replace(array_keys($placeholders), array_values($placeholders), $contents);
    }
}
