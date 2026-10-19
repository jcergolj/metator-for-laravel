<?php

declare(strict_types=1);

require getenv('METATOR_TEST_AUTOLOAD') ?: dirname(__DIR__).'/vendor/autoload.php';
require_once dirname(__DIR__).'/src/Remote/RemoteScriptRunner.php';

use Illuminate\Filesystem\Filesystem;
use Jcergolj\MetatorForLaravel\Remote\RemoteScriptRunner;

function check(bool $condition, string $message): void
{
    if (! $condition) {
        throw new RuntimeException($message);
    }
}

$files = new Filesystem;
$root = sys_get_temp_dir().'/metator-review-'.bin2hex(random_bytes(8));
$home = getenv('HOME');
$path = getenv('PATH');
$before = glob(sys_get_temp_dir().'/metator-*') ?: [];
try {
    $files->makeDirectory($root.'/bin', 0700, true);
    $files->makeDirectory($root.'/home/.ssh', 0700, true);
    $files->makeDirectory($root.'/scripts/steps', 0700, true);
    $files->put($root.'/scripts/server-bootstrap.sh', "#!/bin/bash\n");
    $files->put($root.'/scripts/steps/02-deployer-login.sh', '# selected');
    // Stop before SSH; inspect the actual archive passed to scp.
    $files->put($root.'/bin/scp', "#!/bin/bash\nset -eu\ntar -tzf \"\$4\" > \"\$HOME/archive-list\"\nif grep -qx './.env-seed' \"\$HOME/archive-list\"; then\n  tar -xOzf \"\$4\" ./.env-seed > \"\$HOME/environment-seed\"\n  tar -tvzf \"\$4\" ./.env-seed > \"\$HOME/environment-mode\"\nfi\nexit 19\n");
    chmod($root.'/bin/scp', 0700);
    putenv('HOME='.$root.'/home');
    putenv('PATH='.$root.'/bin:'.$path);
    $runner = new RemoteScriptRunner($files);
    $site = ['site_id' => 'review', 'ssh' => ['user' => 'root', 'host' => 'example.test']];
    $run = function (string $operation, ?string $input = null) use ($runner, $site, $root): void {
        check($runner->run($site, $operation, $root.'/scripts', static function (): void {}, $input) === 19, 'Transfer failure must propagate');
    };
    $files->put($root.'/scripts/.client-public-key', 'stale');
    $files->put($root.'/scripts/.cloudflare.env', 'stale');
    $run('prepare-server');
    $listing = $files->get($root.'/home/archive-list');
    check(! str_contains($listing, '.client-public-key'), 'Preparation must not require or transfer a key');
    check(! str_contains($listing, '.cloudflare.env'), 'Stale credentials must not be transferred');

    $files->put($root.'/input', "APP_NAME=Review\n");
    $run('update-environment', $root.'/input');
    check(str_contains($files->get($root.'/home/archive-list'), '.env-input'), 'Environment input missing');

    $files->put($root.'/home/.ssh/named-key.pub', 'ssh-ed25519 AAAATEST test key');
    $localEnvironment = "# Custom application settings\nAPP_ENV=local\nAPP_DEBUG=true\nAPP_KEY=base64:local-key\n\nCUSTOM_SECRET='literal __DOMAIN__ value'\n";
    $files->put($root.'/.env', $localEnvironment);
    $run('provision');
    check(str_contains($files->get($root.'/home/archive-list'), '.client-public-key'), 'Provisioning key missing');
    check($files->exists($root.'/home/environment-seed'), 'Local environment seed missing');
    check($files->get($root.'/home/environment-seed') === $localEnvironment, 'Local environment must be transferred byte for byte');
    check(str_starts_with($files->get($root.'/home/environment-mode'), '-rw-------'), 'Environment seed must have private permissions');
    check(! $files->exists($root.'/scripts/.env-seed'), 'Secrets must not be written into generated scaffolding');
    $run('prepare-server');
    check(! str_contains($files->get($root.'/home/archive-list'), '.env-seed'), 'Preparation must not transfer the local environment');
    $run('provision', $root.'/input');
    check(str_contains($files->get($root.'/home/archive-list'), '.client-public-key'), 'Key missing when supplying environment input');
    $files->delete($root.'/home/.ssh/named-key.pub');
    try {
        $run('provision');
        throw new LogicException('Missing key should fail');
    } catch (RuntimeException $exception) {
        check(str_contains($exception->getMessage(), 'No valid local public SSH key'), 'Unexpected failure');
    }
    $files->delete($root.'/scripts/steps/02-deployer-login.sh');
    $run('provision');
    check(! str_contains($files->get($root.'/home/archive-list'), '.client-public-key'), 'Unselected login should not require a key');
    $files->delete($root.'/.env');
    try {
        $run('provision');
        throw new LogicException('Missing local environment should fail');
    } catch (RuntimeException $exception) {
        check(str_contains($exception->getMessage(), 'local application .env'), 'Missing local environment must have an actionable error');
    }

    $files->put($root.'/bin/scp', "#!/bin/bash\nexit 0\n");
    $files->put($root.'/bin/ssh', <<<'BASH'
#!/bin/bash
set -eu
[[ "$1" == '-tt' ]] || { echo 'Remote sudo requires a terminal' >&2; exit 1; }
[[ "$2" == '-o' && "$3" == 'BatchMode=yes' ]] || exit 2
[[ "$4" == 'root@example.test' ]] || exit 3
[[ "$5" == *'METATOR_OPERATION='* ]] || exit 4
echo 'remote output'
exit 23
BASH
    );
    chmod($root.'/bin/ssh', 0700);
    $output = '';
    $status = $runner->run($site, 'prepare-server', $root.'/scripts', static function (string $chunk) use (&$output): void {
        $output .= $chunk;
    });
    check($status === 23, 'TTY-enabled SSH must preserve the remote exit status');
    check(str_contains($output, 'remote output'), 'TTY-enabled SSH must stream remote output');
} finally {
    putenv($home === false ? 'HOME' : 'HOME='.$home);
    putenv($path === false ? 'PATH' : 'PATH='.$path);
    $files->deleteDirectory($root);
}
check(array_diff(glob(sys_get_temp_dir().'/metator-*') ?: [], $before) === [], 'Temporary files leaked');
echo "Remote staging checks passed.\n";
