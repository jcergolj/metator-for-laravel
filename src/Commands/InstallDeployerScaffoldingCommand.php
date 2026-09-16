<?php

namespace Jcergolj\MetatorForLaravel\Commands;

use Illuminate\Console\Command;
use Illuminate\Filesystem\Filesystem;
use function Laravel\Prompts\confirm;
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
        $configName = text(
            label: __('Configuration name'),
            default: 'production',
            required: true,
            validate: fn (string $value): ?string => preg_match('/^[a-z][a-z0-9-]*$/', $value) === 1
                ? null
                : __('Use lowercase letters, numbers, and hyphens, starting with a letter.'),
        );
        $repository = text(
            label: __('GitHub repository (owner/repository)'),
            default: 'jcergolj/'.$project,
            required: true,
            validate: function (string $value): ?string {
                return preg_match('/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/', $value) !== 1
                    ? __('Repository must look like owner/repository.')
                    : null;
            },
        );
        $suggestedSiteId = $this->suggestedSiteId($repository, $configName);
        $siteId = text(
            label: __('Site ID'),
            default: $suggestedSiteId,
            required: true,
            validate: fn (string $value): ?string => $this->validSiteId($value)
                ? null
                : __('Use 1-24 lowercase letters or digits, with single hyphens between segments.'),
        );
        $siteConfiguration = $basePath.'/metator.'.$configName.'.php';
        if ($this->files->exists($siteConfiguration) && ! $this->option('force')) {
            $this->error("Site configuration already exists: {$siteConfiguration}. Use --force to replace it.");

            return self::FAILURE;
        }
        $envExample = $basePath.'/.env.example';
        $stepCatalogue = $basePath.'/metator/steps';
        $stepManifest = $stepCatalogue.'/.metator-package-manifest.json';

        if (! $this->files->exists($envExample)) {
            throw new \RuntimeException("Missing application .env.example: {$envExample}");
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
        $redisCapability = select(
            label: __('Redis capability'),
            options: [
                'none' => __('Disabled'),
                'cache' => __('Cache and sessions'),
                'queue' => __('Queues, cache, and sessions'),
            ],
            default: 'none',
        );
        $schedulerEnabled = confirm(label: __('Enable the scheduler?'), default: true);
        if ($workerType === 'horizon' && $redisCapability === 'none') {
            $this->error('Laravel Horizon requires the Redis capability.');

            return self::FAILURE;
        }
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
            '__GITHUB_REPOSITORY__' => $repository,
            '__BRANCH__' => text(
                label: __('Deployment branch'),
                default: 'main',
                required: true,
                validate: function (string $value): ?string {
                    return preg_match('/^[A-Za-z0-9][A-Za-z0-9._\/-]*$/', $value) !== 1
                        ? __('Enter a valid Git branch name.')
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
            '__SSH_USER__' => text(
                label: __('Operator SSH user'),
                default: 'jcergolj',
                required: true,
                validate: function (string $value): ?string {
                    return preg_match('/^[A-Za-z_][A-Za-z0-9_-]*$/', $value) !== 1
                        ? __('Enter a valid SSH username.')
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
            '__PHP_VERSION__' => select(
                label: __('PHP version'),
                options: ['8.4' => __('PHP 8.4'), '8.5' => __('PHP 8.5')],
                default: '8.5',
            ),
            '__CONFIGURE_DEPLOY_USER_LOGIN__' => 'true',
            '__USE_CLOUDFLARE__' => 'true',
            '__USE_SCHEDULER__' => $schedulerEnabled ? 'true' : 'false',
            '__WORKER_TYPE__' => $workerType,
            '__USE_QUEUE__' => $workerType === 'none' ? 'false' : 'true',
            '__USE_HORIZON__' => $workerType === 'horizon' ? 'true' : 'false',
        ];

        $this->files->put($siteConfiguration, "<?php\n\nreturn ".var_export([
            'site_id' => $siteId,
            'ssh' => [
                'host' => $placeholders['__SERVER_IP__'],
                'user' => $placeholders['__SSH_USER__'],
            ],
            'domain' => $placeholders['__DOMAIN__'],
            'repository' => $placeholders['__GITHUB_REPOSITORY__'],
            'php_version' => $placeholders['__PHP_VERSION__'],
            'database' => $placeholders['__DATABASE_DRIVER__'] === 'mysql' ? 'mariadb' : 'sqlite',
            'redis' => $redisCapability,
            'worker' => $workerType,
            'scheduler' => $schedulerEnabled,
        ], true).";\n");
        $this->info("Configured site: {$siteConfiguration}");

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
        $normalizedIds = [];
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
            if (preg_match('/^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/', $metadata['id']) !== 1) {
                throw new \RuntimeException("Step {$file->getFilename()} has invalid @id: {$metadata['id']}.");
            }
            if ($metadata['title'] === '' || $metadata['group'] === '') {
                throw new \RuntimeException("Step {$file->getFilename()} has an empty @title or @group.");
            }
            foreach (['required', 'default'] as $boolean) {
                if (! in_array($metadata[$boolean], ['true', 'false'], true)) {
                    throw new \RuntimeException("Step {$file->getFilename()} has invalid @{$boolean}: {$metadata[$boolean]}.");
                }
            }
            if (preg_match('/^(?:0|[1-9][0-9]*)$/', $metadata['order']) !== 1) {
                throw new \RuntimeException("Step {$file->getFilename()} has invalid @order: {$metadata['order']}.");
            }
            $normalizedId = str_replace('-', '_', $metadata['id']);
            if (isset($normalizedIds[$normalizedId])) {
                throw new \RuntimeException("Steps {$normalizedIds[$normalizedId]} and {$file->getFilename()} collide as {$normalizedId}().");
            }
            $normalizedIds[$normalizedId] = $file->getFilename();
            $steps[] = [
                'id' => $metadata['id'],
                'title' => $metadata['title'],
                'group' => $metadata['group'],
                'required' => $metadata['required'] === 'true',
                'default' => $metadata['default'] === 'true',
                'order' => (int) $metadata['order'],
                'file' => $file->getFilename(),
            ];
            $function = 'step_'.str_replace('-', '_', $metadata['id']);
            if (preg_match('/(?:^|[;\s])(?:function\s+)?'.preg_quote($function, '/').'\s*\(\)\s*\{/', $contents) !== 1) {
                throw new \RuntimeException("Step {$file->getFilename()} must define {$function}().");
            }
        }

        usort($steps, fn (array $left, array $right): int => [$left['order'], str_replace('-', '_', $left['id']), $left['file']]
            <=> [$right['order'], str_replace('-', '_', $right['id']), $right['file']]);

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

    private function validSiteId(string $value): bool
    {
        return strlen($value) <= 24 && preg_match('/^[a-z](?:[a-z0-9]|-(?=[a-z0-9]))*$/', $value) === 1;
    }

    private function suggestedSiteId(string $repository, string $environment): ?string
    {
        $repositoryName = strtolower((string) strrchr($repository, '/'));
        $repositoryName = ltrim($repositoryName, '/');
        $repositoryName = trim((string) preg_replace('/[^a-z0-9]+/', '-', $repositoryName), '-');
        $suggestion = $repositoryName.'-'.$environment;

        return $this->validSiteId($suggestion) ? $suggestion : null;
    }
}
