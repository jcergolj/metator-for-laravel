<?php

declare(strict_types=1);

require getenv('METATOR_TEST_AUTOLOAD') ?: dirname(__DIR__).'/vendor/autoload.php';

use Illuminate\Container\Container;
use Illuminate\Filesystem\Filesystem;
use Jcergolj\MetatorForLaravel\Commands\InstallDeployerScaffoldingCommand;
use Laravel\Prompts\ConfirmPrompt;
use Laravel\Prompts\MultiSelectPrompt;
use Laravel\Prompts\PasswordPrompt;
use Laravel\Prompts\Prompt;
use Laravel\Prompts\SelectPrompt;
use Laravel\Prompts\TextPrompt;
use Symfony\Component\Console\Tester\CommandTester;

// A package test has no Laravel application's translation helper.
function __(string $message, array $replace = []): string
{
    foreach ($replace as $key => $value) {
        $message = str_replace(':'.$key, $value, $message);
    }

    return $message;
}

function check(bool $condition, string $message): void
{
    if (! $condition) {
        throw new RuntimeException($message);
    }
}

function install(string $project, array $answers, bool $force = false, int $expectedStatus = 0): string
{
    $application = new class($project, $answers) extends Container
    {
        public function __construct(private string $project, public array $answers) {}

        public function basePath(string $path = ''): string
        {
            return $this->project.($path === '' ? '' : '/'.$path);
        }

        public function runningUnitTests(): bool
        {
            return true;
        }

        public function call($callback, array $parameters = [], $defaultMethod = null)
        {
            foreach ([TextPrompt::class, SelectPrompt::class, MultiSelectPrompt::class, ConfirmPrompt::class, PasswordPrompt::class] as $type) {
                $type::fallbackUsing(function (Prompt $prompt): mixed {
                    $answer = array_shift($this->answers);

                    check($answer !== null, 'Unexpected prompt: '.$prompt->label);
                    check($answer[0] === $prompt->label, "Expected {$answer[0]}, got {$prompt->label}");
                    if ($answer[1] instanceof Throwable) {
                        throw $answer[1];
                    }
                    if (array_key_exists(2, $answer)) {
                        check($prompt->default === $answer[2], 'Wrong saved default for '.$prompt->label);
                    }

                    return $answer[1];
                });
            }

            return parent::call($callback, $parameters, $defaultMethod);
        }
    };
    $command = $application->make(InstallDeployerScaffoldingCommand::class);
    $command->setLaravel($application);
    $tester = new CommandTester($command);
    $status = $tester->execute($force ? ['--force' => true] : []);

    check($application->answers === [], 'Some expected prompts were not shown.');
    check($status === $expectedStatus, $tester->getDisplay());

    return $tester->getDisplay();
}

$files = new Filesystem;
$directory = '/tmp/opencode/metator-installation-answers-'.bin2hex(random_bytes(8));
$files->makeDirectory($directory, 0700, true);
$files->put($directory.'/.env.example', "APP_NAME=Example\n");

try {
    $catalogue = new Jcergolj\MetatorForLaravel\Commands\StepCatalogue($files);
    $steps = array_column(array_filter($catalogue->available(dirname(__DIR__).'/stubs/scripts/steps'), function (array $step): bool {
        return $step['required'] || $step['default'];
    }), 'id');
    $steps = array_values(array_diff($steps, ['cloudflare']));

    install($directory, [
        ['Configuration name', 'production'],
        ['GitHub repository (owner/repository)', 'acme/shop'],
        ['Site ID', 'production-shop'],
        ['Deployment steps', $steps],
        ['Worker mode', 'none'],
        ['Redis capability', 'none'],
        ['Enable the scheduler?', false],
        ['Deployment branch', 'main'],
        ['Server IP address', '192.0.2.40'],
        ['Operator SSH user', 'operator'],
        ['Production domain', 'shop.example.test'],
        ['Database driver', 'sqlite'],
        ['PHP version', '8.4'],
    ]);

    $sitePath = $directory.'/metator.production.php';
    $site = require $sitePath;
    check($site['branch'] === 'main', 'The deployment branch was not saved.');
    check($site['steps'] === $steps, 'Selected steps were not saved.');

    install($directory, [
        ['Configuration name', 'production'],
        ['Reuse previous settings?', true],
    ], true);

    check((require $sitePath) === $site, 'Reusing answers changed the site configuration.');
    check(str_contains($files->get($directory.'/deploy.php'), "set('branch', 'main')"), 'Reusing answers lost the deployment branch.');

    try {
        install($directory, [
            ['Configuration name', 'staging'],
            ['GitHub repository (owner/repository)', 'acme/staging'],
            ['Site ID', 'staging-shop'],
            ['Deployment steps', array_merge($steps, ['cloudflare'])],
            ['Worker mode', 'none'],
            ['Redis capability', 'none'],
            ['Enable the scheduler?', false],
            ['Cloudflare API token', 'private-test-token'],
            ['Cloudflare zone ID', new RuntimeException('Interrupted setup')],
        ]);
        throw new RuntimeException('The setup interruption was not simulated.');
    } catch (RuntimeException $exception) {
        check($exception->getMessage() === 'Interrupted setup', $exception->getMessage());
    }

    $draftPath = $directory.'/.metator.staging.answers.json';
    check(is_file($draftPath), 'Interrupted answers were not saved.');
    check(! str_contains($files->get($draftPath), 'private-test-token'), 'A secret leaked into the answer draft.');
    check((fileperms($directory.'/metator.staging.local.php') & 0777) === 0600, 'The saved secret is not private.');
    check(str_contains($files->get($directory.'/.gitignore'), '/metator.*.local.php'), 'Saved secrets are not Git-ignored.');

    $output = install($directory, [
        ['Configuration name', 'staging'],
        ['Reuse previous settings?', true],
        ['Cloudflare zone ID', 'abc123'],
        ['Deployment branch', 'develop'],
        ['Server IP address', '192.0.2.50'],
        ['Operator SSH user', 'stagingoperator'],
        ['Production domain', 'staging.example.test'],
        ['Database driver', 'sqlite'],
        ['PHP version', '8.5'],
    ]);

    check(! str_contains($output, 'private-test-token'), 'A saved token appeared in the summary.');
    check(str_contains($output, 'Saved value'), 'The saved settings summary was not displayed.');
    check(str_contains($output, 'acme/staging'), 'The summary did not show the saved repository.');
    check(str_contains($output, 'Saved (hidden)'), 'The summary did not identify the saved, hidden token.');
    check(! is_file($draftPath), 'Successful setup did not remove the draft.');
    check((require $sitePath) === $site, 'Staging setup changed production settings.');
    check((require $directory.'/metator.staging.php')['repository'] === 'acme/staging', 'Staging reused production answers.');

    install($directory, [
        ['Configuration name', 'production'],
        ['Reuse previous settings?', false],
        ['Settings to change', ['branch', 'domain']],
        ['Deployment branch', 'release', 'main'],
        ['Production domain', 'new-shop.example.test', 'shop.example.test'],
    ], true);

    $updated = require $sitePath;
    check($updated['branch'] === 'release', 'The selected branch edit was not saved.');
    check($updated['domain'] === 'new-shop.example.test', 'The selected domain edit was not saved.');
    check($updated['scheduler'] === false, 'A saved false answer reverted to its default.');
    check($updated['site_id'] === 'production-shop', 'Editing other fields changed the site ID.');

    try {
        install($directory, [
            ['Configuration name', 'production'],
            ['Reuse previous settings?', false],
            ['Settings to change', ['branch', 'domain']],
            ['Deployment branch', 'hotfix', 'release'],
            ['Production domain', new RuntimeException('Interrupted edit')],
        ], true);
        throw new RuntimeException('The edit interruption was not simulated.');
    } catch (RuntimeException $exception) {
        check($exception->getMessage() === 'Interrupted edit', $exception->getMessage());
    }

    install($directory, [
        ['Configuration name', 'production'],
        ['Reuse previous settings?', true],
    ], true);

    check((require $sitePath)['branch'] === 'hotfix', 'An interrupted edit lost the newly saved branch.');

    $manuallyEdited = require $sitePath;
    $manuallyEdited['node'] = true;
    $files->put($sitePath, "<?php\nreturn ".var_export($manuallyEdited, true).";\n");
    install($directory, [
        ['Configuration name', 'production'],
        ['Reuse previous settings?', true],
    ], true);

    check((require $sitePath)['node'] === true, 'Reusing answers ignored the completed Node capability.');
    check(is_file($directory.'/scripts/steps/11-node.sh'), 'The saved Node capability did not select its step.');

    $stagingPath = $directory.'/metator.staging.php';
    $staging = require $stagingPath;
    $staging['cloudflare'] = false;
    $files->put($stagingPath, "<?php\nreturn ".var_export($staging, true).";\n");
    install($directory, [
        ['Configuration name', 'staging'],
        ['Reuse previous settings?', true],
    ], true);

    check((require $stagingPath)['cloudflare'] === false, 'Reusing answers ignored the completed Cloudflare capability.');
    check(! is_file($directory.'/scripts/steps/02-cloudflare.sh'), 'A disabled Cloudflare capability retained its generated step.');

    $files->put($directory.'/deploy.php', "<?php\n// Operator customization\n");
    $configuration = $files->get($sitePath);
    $output = install($directory, [['Configuration name', 'production']], expectedStatus: 1);

    check(str_contains($output, 'Use --force'), 'The overwrite warning was not displayed.');
    check($files->get($sitePath) === $configuration, 'A rerun without --force overwrote the configuration.');
    check($files->get($directory.'/deploy.php') === "<?php\n// Operator customization\n", 'A rerun without --force overwrote custom deployment tasks.');
} finally {
    $files->deleteDirectory($directory);
}

echo "Installation answer checks passed.\n";
