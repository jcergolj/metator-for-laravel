<?php

declare(strict_types=1);

require getenv('METATOR_TEST_AUTOLOAD') ?: dirname(__DIR__).'/vendor/autoload.php';

use Illuminate\Filesystem\Filesystem;
use Jcergolj\MetatorForLaravel\Commands\GeneratedFileWriter;
use Jcergolj\MetatorForLaravel\Commands\StepCatalogue;

$root = dirname(__DIR__);
$directory = sys_get_temp_dir().'/metator-generated-preservation-'.bin2hex(random_bytes(8));
$project = $directory.'/project';
$stepDirectory = $project.'/metator/steps';
$packageSteps = $root.'/stubs/scripts/steps';
$files = new Filesystem;
$files->makeDirectory($stepDirectory, 0700, true);

try {
    $catalogue = new StepCatalogue($files);
    $manifest = $stepDirectory.'/.metator-package-manifest.json';
    $catalogue->publish($packageSteps, $stepDirectory, $manifest, true);

    $customStep = $stepDirectory.'/custom-check.sh';
    $customStepContents = "# Operator-owned custom step\nstep_custom_check() { return 0; }\n";
    $files->put($customStep, $customStepContents);
    $catalogue->publish($packageSteps, $stepDirectory, $manifest, true);
    if ($files->get($customStep) !== $customStepContents) {
        throw new RuntimeException('Forced package-step refresh changed an operator-owned custom step.');
    }

    $customRecipe = "<?php\n// Operator-owned deployment tasks\n";
    $files->put($project.'/deploy.php', $customRecipe);
    $files->put($project.'/.env.example', "APP_NAME=Acceptance\nAPP_ENV=production\nAPP_KEY=\nAPP_DEBUG=false\nAPP_URL=https://example.test\n");

    $placeholders = [
        '__APP_NAME__' => 'acceptance',
        '__CONFIG_FILE__' => 'metator.acceptance.php',
        '__DEPLOY_PATH__' => '/var/www/acceptance',
        '__SITE_ID__' => 'acceptance',
        '__GITHUB_REPOSITORY__' => 'owner/application',
        '__BRANCH__' => 'main',
        '__SERVER_IP__' => '192.0.2.10',
        '__SSH_USER__' => 'operator',
        '__GIT_DEPLOYER_NAME__' => 'git-acceptance',
        '__DOMAIN__' => 'acceptance.example.test',
        '__DATABASE_DRIVER__' => 'sqlite',
        '__PHP_VERSION__' => '8.5',
        '__CONFIGURE_DEPLOY_USER_LOGIN__' => 'true',
        '__USE_CLOUDFLARE__' => 'false',
        '__USE_SCHEDULER__' => 'false',
        '__WORKER_TYPE__' => 'none',
        '__USE_QUEUE__' => 'false',
        '__USE_HORIZON__' => 'false',
        '__USE_REDIS__' => 'false',
        '__REDIS_CAPABILITY__' => 'none',
    ];
    $installation = [
        'placeholders' => $placeholders,
        'selected_steps' => [],
        'site_configuration' => $project.'/metator.acceptance.php',
        'secret_configuration' => $project.'/metator.acceptance.local.php',
        'env_example' => $project.'/.env.example',
        'config_name' => 'acceptance',
        'cloudflare_secrets' => null,
    ];

    (new GeneratedFileWriter($files))->write(
        $installation,
        $root.'/stubs',
        $project,
        $stepDirectory,
        false,
        static function (string $message): void {},
        static function (string $message): void {},
    );
    if ($files->get($project.'/deploy.php') !== $customRecipe) {
        throw new RuntimeException('Normal scaffolding installation replaced the operator-edited deploy.php.');
    }
} finally {
    $files->deleteDirectory($directory);
}

fwrite(STDOUT, "Generated file preservation checks passed.\n");
