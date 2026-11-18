<?php

declare(strict_types=1);

namespace Jcergolj\MetatorForLaravel\Commands;

use function Laravel\Prompts\confirm;
use function Laravel\Prompts\multiselect;
use function Laravel\Prompts\password;
use function Laravel\Prompts\select;
use function Laravel\Prompts\text;

final class InstallationPrompts
{
    public function __construct(private InstallationAnswers $answers)
    {
    }

    public function collect(string $basePath, string $stepCatalogue, StepCatalogue $catalogue, callable $error, bool $force = false): ?array
    {
        $project = basename($basePath);
        $configName = text(label: __('Configuration name'), default: 'production', required: true, validate: fn (string $value): ?string => preg_match('/^[a-z][a-z0-9-]*$/', $value) === 1 ? null : __('Use lowercase letters, numbers, and hyphens, starting with a letter.'));
        if (is_file($basePath.'/metator.'.$configName.'.php') && ! $force) {
            $error(__('Site configuration already exists: :path. Use --force to replace it.', ['path' => $basePath.'/metator.'.$configName.'.php']));

            return null;
        }
        $this->answers->load($basePath, $configName);
        $repository = $this->answers->ask('repository', fn (?string $saved): string => text(label: __('GitHub repository (owner/repository)'), default: $saved ?? 'jcergolj/'.$project, required: true, validate: fn (string $value): ?string => preg_match('/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/', $value) === 1 ? null : __('Repository must look like owner/repository.')));
        $suggestedSiteId = $this->suggestedSiteId($repository, $configName);
        $siteId = $this->answers->ask('site_id', fn (?string $saved): string => text(label: __('Site ID'), default: $saved ?? $suggestedSiteId ?? '', required: true, validate: fn (string $value): ?string => $this->validSiteId($value) ? null : __('Use 1-32 lowercase letters or digits, with single hyphens between segments, starting with a letter.')));
        $availableSteps = $catalogue->available($stepCatalogue);
        $selectedStepIds = $this->answers->ask('steps', fn (?array $saved): array => multiselect(label: __('Deployment steps'), options: array_column($availableSteps, 'title', 'id'), default: $saved ?? array_column(array_filter($availableSteps, fn (array $step): bool => $step['default']), 'id'), required: true, hint: __('Select the steps that should be included in the generated server scripts.')));
        $workerType = $this->answers->ask('worker', fn (?string $saved): string => select(label: __('Worker mode'), options: ['none' => __('No workers'), 'queue' => __('Standard queue workers'), 'horizon' => __('Laravel Horizon')], default: $saved ?? 'none'));
        $redisCapability = $this->answers->ask('redis', fn (?string $saved): string => select(label: __('Redis capability'), options: ['none' => __('Disabled'), 'cache' => __('Cache and sessions'), 'queue' => __('Queues, cache, and sessions')], default: $saved ?? 'none'));
        $schedulerEnabled = $this->answers->ask('scheduler', fn (?bool $saved): bool => confirm(label: __('Enable the scheduler?'), default: $saved ?? true));
        if ($workerType === 'horizon' && $redisCapability !== 'queue') {
            $error('Laravel Horizon requires the Redis queues capability.');

            return null;
        }
        $selectedStepIds = array_values(array_filter($selectedStepIds, fn (string $id): bool => $id !== 'workers'));
        if ($workerType !== 'none') {
            $selectedStepIds[] = 'workers';
        }
        $selectedStepIds = array_values(array_filter($selectedStepIds, fn (string $id): bool => $id !== 'redis'));
        if ($redisCapability !== 'none') {
            $selectedStepIds[] = 'redis';
        }
        $selectedSteps = array_values(array_filter($availableSteps, fn (array $step): bool => in_array($step['id'], $selectedStepIds, true)));
        $catalogue->validateSelection($availableSteps, $selectedSteps);

        $cloudflareSecrets = in_array('cloudflare', $selectedStepIds, true) ? [
            'token' => $this->answers->ask('cloudflare_token', fn (): string => password(label: __('Cloudflare API token'), required: true)),
            'zone_id' => $this->answers->ask('cloudflare_zone', fn (?string $saved): string => text(label: __('Cloudflare zone ID'), default: $saved ?? '', required: true, validate: fn (string $value): ?string => preg_match('/^[A-Za-z0-9]+$/', $value) === 1 ? null : __('Enter a valid Cloudflare zone ID.'))),
        ] : null;

        $branch = $this->answers->ask('branch', fn (?string $saved): string => text(label: __('Deployment branch'), default: $saved ?? 'master', required: true, validate: fn (string $value): ?string => preg_match('/^[A-Za-z0-9][A-Za-z0-9._\/-]*$/', $value) === 1 ? null : __('Enter a valid Git branch name.')));
        $serverIp = $this->answers->ask('host', fn (?string $saved): string => text(label: __('Server IP address'), default: $saved ?? '', required: true, validate: fn (string $value): ?string => filter_var($value, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) === false ? __('Enter a valid IPv4 address.') : null));
        $sshUser = $this->answers->ask('ssh_user', fn (?string $saved): string => text(label: __('Operator SSH user'), default: $saved ?? 'jcergolj', required: true, validate: fn (string $value): ?string => preg_match('/^[A-Za-z_][A-Za-z0-9_-]*$/', $value) === 1 ? null : __('Enter a valid SSH username.')));
        $domain = $this->answers->ask('domain', fn (?string $saved): string => text(label: __('Production domain'), default: $saved ?? '', required: true, validate: fn (string $value): ?string => preg_match('/^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/', $value) === 1 ? null : __('Enter a valid domain.')));
        $databaseDriver = $this->answers->ask('database', fn (?string $saved): string => select(label: __('Database driver'), options: ['sqlite' => __('SQLite'), 'mysql' => __('MySQL')], default: $saved ?? 'sqlite'));
        $phpVersion = $this->answers->ask('php_version', fn (?string $saved): string => select(label: __('PHP version'), options: ['8.4' => __('PHP 8.4'), '8.5' => __('PHP 8.5')], default: $saved ?? '8.5'));

        return [
            'config_name' => $configName,
            'site_configuration' => $basePath.'/metator.'.$configName.'.php',
            'secret_configuration' => $basePath.'/metator.'.$configName.'.local.php',
            'env_example' => $basePath.'/.env.example',
            'selected_steps' => $selectedSteps,
            'cloudflare_secrets' => $cloudflareSecrets,
            'placeholders' => [
                '__APP_NAME__' => $project,
                '__CONFIG_FILE__' => 'metator.'.$configName.'.php',
                '__DEPLOY_PATH__' => '/var/www/'.$siteId,
                '__SITE_ID__' => $siteId,
                '__GITHUB_REPOSITORY__' => $repository,
                '__BRANCH__' => $branch,
                '__SERVER_IP__' => $serverIp,
                '__SSH_USER__' => $sshUser,
                '__GIT_DEPLOYER_NAME__' => 'git-'.$siteId,
                '__DOMAIN__' => $domain,
                '__DATABASE_DRIVER__' => $databaseDriver,
                '__PHP_VERSION__' => $phpVersion,
                '__CONFIGURE_DEPLOY_USER_LOGIN__' => 'true',
                '__USE_CLOUDFLARE__' => 'true',
                '__USE_SCHEDULER__' => $schedulerEnabled ? 'true' : 'false',
                '__WORKER_TYPE__' => $workerType,
                '__USE_QUEUE__' => $workerType === 'none' ? 'false' : 'true',
                '__USE_HORIZON__' => $workerType === 'horizon' ? 'true' : 'false',
                '__USE_REDIS__' => $redisCapability === 'none' ? 'false' : 'true',
                '__REDIS_CAPABILITY__' => $redisCapability,
            ],
        ];
    }

    private function validSiteId(string $value): bool
    {
        return strlen($value) <= 32 && preg_match('/^[a-z](?:[a-z0-9]|-(?=[a-z0-9]))*$/', $value) === 1;
    }

    private function suggestedSiteId(string $repository, string $environment): ?string
    {
        $name = trim((string) preg_replace('/[^a-z0-9]+/', '-', strtolower((string) strrchr($repository, '/'))), '-');
        $suggestion = $environment.'-'.$name;
        return $this->validSiteId($suggestion) ? $suggestion : null;
    }
}
