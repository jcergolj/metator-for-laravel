<?php

declare(strict_types=1);

require getenv('METATOR_TEST_AUTOLOAD') ?: dirname(__DIR__).'/vendor/autoload.php';
require_once dirname(__DIR__).'/src/Remote/RemoteScriptRunner.php';
require_once dirname(__DIR__).'/src/Commands/RunRemoteProvisioningCommand.php';

use Illuminate\Console\OutputStyle;
use Illuminate\Container\Container;
use Illuminate\Filesystem\Filesystem;
use Jcergolj\MetatorForLaravel\Commands\RunRemoteProvisioningCommand;
use Jcergolj\MetatorForLaravel\Remote\RemoteScriptRunner;
use Symfony\Component\Console\Input\ArrayInput;
use Symfony\Component\Console\Output\BufferedOutput;

final class RegistrationRunner extends RemoteScriptRunner
{
    public int $calls = 0;

    public function __construct(private array $statuses)
    {
        parent::__construct(new Filesystem);
    }

    public function run(array $site, string $operation, string $scriptsPath, callable $output, ?string $environmentInput = null): int
    {
        $this->calls++;
        $output("Deploy-key settings: https://github.com/acme/site/settings/keys\nssh-ed25519 AAAATEST\n", false);

        return array_shift($this->statuses) ?? throw new RuntimeException('Unexpected retry');
    }
}

final class RegistrationCommand extends RunRemoteProvisioningCommand
{
    protected function loadSite(): array
    {
        return [];
    }

    public function invoke(ArrayInput $input, BufferedOutput $output, string $operation): int
    {
        $this->input = $input;
        $this->output = new OutputStyle($input, $output);
        $this->setLaravel(new class extends Container {
            public function basePath(string $path): string
            {
                return '/test/'.$path;
            }
        });

        return $this->runOperation($operation);
    }
}

foreach ([
    [[75, 0], "yes\n", true, 'provision', 0, 2, true],
    [[75, 75, 0], "yes\nyes\n", true, 'provision', 0, 3, true],
    [[75], "no\n", true, 'provision', 1, 1, true],
    [[75], '', false, 'provision', 1, 1, false],
    [[1], '', true, 'provision', 1, 1, false],
    [[75], '', true, 'prepare-server', 1, 1, false],
] as [$statuses, $answer, $interactive, $operation, $expectedStatus, $calls, $prompt]) {
    $runner = new RegistrationRunner($statuses);
    $command = new RegistrationCommand($runner);
    $input = new ArrayInput([]);
    $input->setInteractive($interactive);
    $stream = fopen('php://memory', 'r+');
    fwrite($stream, $answer);
    rewind($stream);
    $input->setStream($stream);
    $output = new BufferedOutput;
    $status = $command->invoke($input, $output, $operation);
    fclose($stream);
    $text = $output->fetch();
    if ($status !== $expectedStatus || $runner->calls !== $calls || str_contains($text, 'Ready to verify access') !== $prompt) {
        throw new RuntimeException('Unexpected confirmation behavior: '.$text);
    }
    if ($prompt && strpos($text, 'ssh-ed25519 AAAATEST') > strpos($text, 'Ready to verify access')) {
        throw new RuntimeException('Key must be displayed before prompting');
    }
}
echo "Registration confirmation checks passed.\n";
