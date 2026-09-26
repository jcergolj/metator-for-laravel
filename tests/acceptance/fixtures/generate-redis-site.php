<?php

declare(strict_types=1);

use Illuminate\Filesystem\Filesystem;
use Jcergolj\MetatorForLaravel\Commands\GeneratedFileWriter;
use Jcergolj\MetatorForLaravel\Commands\StepCatalogue;

[$script, $projectRoot, $packageRoot, $siteId, $serverIp, $operatorUser] = $argv + array_fill(0, 6, null);
if (! is_string($projectRoot) || ! is_string($packageRoot) || ! is_string($siteId)
    || ! is_string($serverIp) || ! is_string($operatorUser)) {
    fwrite(STDERR, "Usage: generate-redis-site.php <project> <package> <site-id> <server-ip> <operator-user>\n");
    exit(2);
}

require $projectRoot.'/vendor/autoload.php';

$files = new Filesystem;
$catalogue = new StepCatalogue($files);
$stepDirectory = $projectRoot.'/metator/steps';
$catalogue->publish(
    $packageRoot.'/stubs/scripts/steps',
    $stepDirectory,
    $stepDirectory.'/.metator-package-manifest.json',
    true,
);
$availableSteps = $catalogue->available($stepDirectory);
$selectedSteps = array_values(array_filter(
    $availableSteps,
    static fn (array $step): bool => ($step['default'] && $step['id'] !== 'scheduler')
        || in_array($step['id'], ['redis', 'workers'], true),
));
$catalogue->validateSelection($availableSteps, $selectedSteps);

$domain = $siteId.'.'.$serverIp.'.sslip.io';
$configName = 'acceptance';
$placeholders = [
    '__APP_NAME__' => basename($projectRoot),
    '__CONFIG_FILE__' => 'metator.'.$configName.'.php',
    '__DEPLOY_PATH__' => '/var/www/'.$siteId,
    '__SITE_ID__' => $siteId,
    '__GITHUB_REPOSITORY__' => 'jcergolj/simpletimer',
    '__BRANCH__' => 'master',
    '__SERVER_IP__' => $serverIp,
    '__SSH_USER__' => $operatorUser,
    '__GIT_DEPLOYER_NAME__' => 'git-'.$siteId,
    '__DOMAIN__' => $domain,
    '__DATABASE_DRIVER__' => 'sqlite',
    '__PHP_VERSION__' => '8.5',
    '__CONFIGURE_DEPLOY_USER_LOGIN__' => 'true',
    '__USE_CLOUDFLARE__' => 'false',
    '__USE_SCHEDULER__' => 'false',
    '__WORKER_TYPE__' => 'queue',
    '__USE_QUEUE__' => 'true',
    '__USE_HORIZON__' => 'false',
    '__USE_REDIS__' => 'true',
    '__REDIS_CAPABILITY__' => 'queue',
];

$installation = [
    'placeholders' => $placeholders,
    'selected_steps' => $selectedSteps,
    'site_configuration' => $projectRoot.'/metator.'.$configName.'.php',
    'secret_configuration' => $projectRoot.'/metator.'.$configName.'.local.php',
    'env_example' => $projectRoot.'/.env.example',
    'config_name' => $configName,
    'cloudflare_secrets' => null,
];

(new GeneratedFileWriter($files))->write(
    $installation,
    $packageRoot.'/stubs',
    $projectRoot,
    $stepDirectory,
    true,
    static function (string $message): void {},
    static function (string $message): void {},
);

printf("Generated Redis acceptance site %s at %s\n", $siteId, $domain);
