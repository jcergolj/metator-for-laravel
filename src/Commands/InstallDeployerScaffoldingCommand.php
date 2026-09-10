<?php

namespace Jcergolj\MetatorForLaravel\Commands;

use Illuminate\Console\Command;
use Illuminate\Filesystem\Filesystem;
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
        $placeholders = [
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
                required: true,
                validate: function (string $value): ?string {
                    return preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]*$/', $value) !== 1
                        ? __('Use only letters, numbers, dots, underscores, and hyphens.')
                        : null;
                },
            ),
        ];
        $targets = [
            'deploy.php.stub' => $basePath.'/deploy.php',
            'scripts/server-bootstrap.sh' => $basePath.'/scripts/server-bootstrap.sh',
            'scripts/lib/common.sh' => $basePath.'/scripts/lib/common.sh',
            'scripts/steps/01-prerequisites.sh' => $basePath.'/scripts/steps/01-prerequisites.sh',
            'scripts/steps/02-deployer-login.sh' => $basePath.'/scripts/steps/02-deployer-login.sh',
            'scripts/steps/02-cloudflare.sh' => $basePath.'/scripts/steps/02-cloudflare.sh',
            'scripts/steps/03-github-key.sh' => $basePath.'/scripts/steps/03-github-key.sh',
            'scripts/steps/04-shared-env.sh' => $basePath.'/scripts/steps/04-shared-env.sh',
            'scripts/steps/05-database.sh' => $basePath.'/scripts/steps/05-database.sh',
            'scripts/steps/06-permissions.sh' => $basePath.'/scripts/steps/06-permissions.sh',
            'scripts/steps/07-caddy.sh' => $basePath.'/scripts/steps/07-caddy.sh',
            'scripts/steps/08-scheduler.sh' => $basePath.'/scripts/steps/08-scheduler.sh',
            'scripts/steps/09-workers.sh' => $basePath.'/scripts/steps/09-workers.sh',
            'scripts/steps/10-deployer-instructions.sh' => $basePath.'/scripts/steps/10-deployer-instructions.sh',
        ];

        foreach ($targets as $stub => $target) {
            $this->copyStub($stubRoot.'/'.$stub, $target, $placeholders);
        }

        $this->info('Metator scaffolding installed.');
        $this->line('Next steps:');
        $this->line('  1. Review deploy.php');
        $this->line('  2. Copy ./scripts to the server and run ./scripts/server-bootstrap.sh');

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
        $project = basename($this->laravel->basePath());

        return str_replace(
            [
                '__APP_NAME__',
                '__DEPLOY_PATH__',
                '__GITHUB_REPOSITORY__',
                ...array_keys($placeholders),
            ],
            [
                $project,
                '/var/www/'.$project,
                'jcergolj/'.$project,
                ...array_values($placeholders),
            ],
            $contents,
        );
    }
}
