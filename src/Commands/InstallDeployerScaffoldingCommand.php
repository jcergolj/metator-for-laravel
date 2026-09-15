<?php

namespace Jcergolj\MetatorForLaravel\Commands;

use Illuminate\Console\Command;
use Illuminate\Filesystem\Filesystem;
use function Laravel\Prompts\multiselect;
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
        $stepCatalogue = $basePath.'/metator/steps';
        $stepManifest = $stepCatalogue.'/.metator-package-manifest.json';

        if (! $this->files->exists($envExample)) {
            throw new \RuntimeException("Missing .env.example stub: {$envExample}");
        }

        $this->publishStepCatalogue($stubRoot.'/scripts/steps', $stepCatalogue, $stepManifest);
        $availableSteps = $this->availableSteps($stepCatalogue);
        $selectedStepIds = multiselect(
            label: __('Deployment steps'),
            options: array_column($availableSteps, 'title', 'id'),
            default: array_column(array_filter($availableSteps, fn (array $step): bool => $step['default']), 'id'),
            required: true,
            hint: __('Select the steps that should be included in the generated server scripts.'),
        );
        $workerType = select(
            label: __('Worker mode'),
            options: ['none' => __('No workers'), 'queue' => __('Standard queue workers'), 'horizon' => __('Laravel Horizon')],
            default: 'none',
        );
        $selectedStepIds = array_values(array_filter($selectedStepIds, fn (string $id): bool => $id !== 'workers'));
        if ($workerType !== 'none') {
            $selectedStepIds[] = 'workers';
        }
        $selectedSteps = array_values(array_filter(
            $availableSteps,
            fn (array $step): bool => in_array($step['id'], $selectedStepIds, true),
        ));

        $this->validateSelectedSteps($availableSteps, $selectedSteps);

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
            '__CONFIGURE_DEPLOY_USER_LOGIN__' => 'true',
            '__USE_CLOUDFLARE__' => 'true',
            '__USE_SCHEDULER__' => 'true',
            '__WORKER_TYPE__' => $workerType,
            '__USE_QUEUE__' => $workerType === 'none' ? 'false' : 'true',
            '__USE_HORIZON__' => $workerType === 'horizon' ? 'true' : 'false',
        ];

        $targets = [
            'deploy.php.stub' => $basePath.'/deploy.php',
            'scripts/server-bootstrap.sh' => $basePath.'/scripts/server-bootstrap.sh',
            'scripts/lib/common.sh' => $basePath.'/scripts/lib/common.sh',
            'scripts/steps/10-deployer-instructions.sh' => $basePath.'/scripts/steps/10-deployer-instructions.sh',
        ];

        foreach ($targets as $stub => $target) {
            $this->copyStub($stubRoot.'/'.$stub, $target, $placeholders);
        }
        $this->writeSelectedSteps($selectedSteps, $stepCatalogue, $basePath.'/scripts/steps', $placeholders);
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

    protected function publishStepCatalogue(string $source, string $target, string $manifest): void
    {
        $this->files->ensureDirectoryExists($target);
        $packageFiles = $this->files->files($source);
        $knownPackageFiles = $this->files->exists($manifest)
            ? json_decode($this->files->get($manifest), true, flags: JSON_THROW_ON_ERROR)
            : [];

        foreach ($packageFiles as $file) {
            $destination = $target.'/'.$file->getFilename();
            if (! $this->files->exists($destination) || ($this->option('force') && in_array($file->getFilename(), $knownPackageFiles, true))) {
                $this->files->copy($file->getPathname(), $destination);
            }
        }

        $this->files->put($manifest, json_encode(
            array_values(array_unique(array_merge($knownPackageFiles, array_map(
                fn (\SplFileInfo $file): string => $file->getFilename(),
                $packageFiles,
            )))),
            JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR,
        ).PHP_EOL);
    }

    /** @return list<array{id: string, title: string, group: string, required: bool, default: bool, order: int, file: string}> */
    protected function availableSteps(string $directory): array
    {
        $steps = [];
        foreach ($this->files->files($directory) as $file) {
            if ($file->getExtension() !== 'sh' || str_starts_with($file->getFilename(), '.')) {
                continue;
            }

            $contents = $this->files->get($file->getPathname());
            $metadata = [];
            foreach (['id', 'title', 'group', 'required', 'default', 'order'] as $key) {
                if (preg_match('/^# @'.preg_quote($key, '/').':[ \t]*(.+)$/m', $contents, $match) === 1) {
                    $metadata[$key] = trim($match[1]);
                }
            }
            foreach (['id', 'title', 'group', 'required', 'default', 'order'] as $key) {
                if (! isset($metadata[$key])) {
                    throw new \RuntimeException("Step {$file->getFilename()} is missing @{$key} metadata.");
                }
            }
            $steps[] = [
                'id' => $metadata['id'],
                'title' => $metadata['title'],
                'group' => $metadata['group'],
                'required' => filter_var($metadata['required'], FILTER_VALIDATE_BOOLEAN),
                'default' => filter_var($metadata['default'], FILTER_VALIDATE_BOOLEAN),
                'order' => (int) $metadata['order'],
                'file' => $file->getFilename(),
            ];
            $function = 'step_'.str_replace('-', '_', $metadata['id']);
            if (preg_match('/function\s+'.preg_quote($function, '/').'\s*\(/', $contents) !== 1) {
                throw new \RuntimeException("Step {$file->getFilename()} must define {$function}().");
            }
        }

        usort($steps, fn (array $left, array $right): int => $left['order'] <=> $right['order']);

        return $steps;
    }

    protected function validateSelectedSteps(array $availableSteps, array $selectedSteps): void
    {
        foreach ($availableSteps as $step) {
            if ($step['required'] && ! in_array($step['id'], array_column($selectedSteps, 'id'), true)) {
                throw new \RuntimeException("Required step is not selected: {$step['id']}.");
            }
        }

        $groups = [];
        foreach ($selectedSteps as $step) {
            if ($step['group'] !== 'none') {
                $groups[$step['group']][] = $step['id'];
            }
        }
        foreach ($groups as $group => $steps) {
            if (count($steps) > 1) {
                throw new \RuntimeException("Select only one step from the {$group} group.");
            }
        }
    }

    protected function writeSelectedSteps(array $selectedSteps, string $source, string $target, array $placeholders): void
    {
        $manifest = dirname($target).'/.metator-manifest.json';
        if ($this->files->exists($manifest) && ! $this->option('force')) {
            $this->warn("Skipped existing generated steps: {$target}");

            return;
        }
        $oldFiles = $this->files->exists($manifest)
            ? json_decode($this->files->get($manifest), true, flags: JSON_THROW_ON_ERROR)
            : [];
        foreach ($oldFiles as $file) {
            $this->files->delete($target.'/'.$file);
        }
        foreach ($selectedSteps as $step) {
            $this->copyStub($source.'/'.$step['file'], $target.'/'.$step['file'], $placeholders);
        }
        $this->files->put($manifest, json_encode(
            array_column($selectedSteps, 'file'),
            JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR,
        ).PHP_EOL);
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
