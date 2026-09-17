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
    public function collect(string $basePath, string $stepCatalogue, StepCatalogue $catalogue, callable $error): ?array
    {
        $project = basename($basePath);
        $configName = text(label: __('Configuration name'), default: 'production', required: true, validate: fn (string $value): ?string => preg_match('/^[a-z][a-z0-9-]*$/', $value) === 1 ? null : __('Use lowercase letters, numbers, and hyphens, starting with a letter.'));
        $repository = text(label: __('GitHub repository (owner/repository)'), default: 'jcergolj/'.$project, required: true, validate: fn (string $value): ?string => preg_match('/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/', $value) === 1 ? null : __('Repository must look like owner/repository.'));
        $suggestedSiteId = $this->suggestedSiteId($repository, $configName);
        $siteId = text(label: __('Site ID'), default: $suggestedSiteId, required: true, validate: fn (string $value): ?string => $this->validSiteId($value) ? null : __('Use 1-24 lowercase letters or digits, with single hyphens between segments.'));
        $availableSteps = $catalogue->available($stepCatalogue);
        $selectedStepIds = multiselect(label: __('Deployment steps'), options: array_column($availableSteps, 'title', 'id'), default: array_column(array_filter($availableSteps, fn (array $step): bool => $step['default']), 'id'), required: true, hint: __('Select the steps that should be included in the generated server scripts.'));
        $workerType = select(label: __('Worker mode'), options: ['none' => __('No workers'), 'queue' => __('Standard queue workers'), 'horizon' => __('Laravel Horizon')], default: 'none');
        $redisCapability = select(label: __('Redis capability'), options: ['none' => __('Disabled'), 'cache' => __('Cache and sessions'), 'queue' => __('Queues, cache, and sessions')], default: 'none');
        $schedulerEnabled = confirm(label: __('Enable the scheduler?'), default: true);
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
            'token' => password(label: __('Cloudflare API token'), required: true),
            'zone_id' => text(label: __('Cloudflare zone ID'), required: true, validate: fn (string $value): ?string => preg_match('/^[A-Za-z0-9]+$/', $value) === 1 ? null : __('Enter a valid Cloudflare zone ID.')),
        ] : null;

        $branch = text(label: __('Deployment branch'), default: 'master', required: true, validate: fn (string $value): ?string => preg_match('/^[A-Za-z0-9][A-Za-z0-9._\/-]*$/', $value) === 1 ? null : __('Enter a valid Git branch name.'));
        $serverIp = text(label: __('Server IP address'), required: true, validate: fn (string $value): ?string => filter_var($value, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) === false ? __('Enter a valid IPv4 address.') : null);
        $sshUser = text(label: __('Operator SSH user'), default: 'jcergolj', required: true, validate: fn (string $value): ?string => preg_match('/^[A-Za-z_][A-Za-z0-9_-]*$/', $value) === 1 ? null : __('Enter a valid SSH username.'));
        $domain = text(label: __('Production domain'), required: true, validate: fn (string $value): ?string => preg_match('/^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/', $value) === 1 ? null : __('Enter a valid domain.'));
        $databaseDriver = select(label: __('Database driver'), options: ['sqlite' => __('SQLite'), 'mysql' => __('MySQL')], default: 'sqlite');
        $phpVersion = select(label: __('PHP version'), options: ['8.4' => __('PHP 8.4'), '8.5' => __('PHP 8.5')], default: '8.5');

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
        return strlen($value) <= 24 && preg_match('/^[a-z](?:[a-z0-9]|-(?=[a-z0-9]))*$/', $value) === 1;
    }

    private function suggestedSiteId(string $repository, string $environment): ?string
    {
        $name = trim((string) preg_replace('/[^a-z0-9]+/', '-', strtolower((string) strrchr($repository, '/'))), '-');
        $suggestion = $name.'-'.$environment;
        return $this->validSiteId($suggestion) ? $suggestion : null;
    }
}
