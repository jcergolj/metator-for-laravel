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
    $files->put($root.'/bin/scp', "#!/bin/bash\nset -eu\ntar -tzf \"\$4\" > \"\$HOME/archive-list\"\nexit 19\n");
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
    $run('provision');
    check(str_contains($files->get($root.'/home/archive-list'), '.client-public-key'), 'Provisioning key missing');
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
} finally {
    putenv($home === false ? 'HOME' : 'HOME='.$home);
    putenv($path === false ? 'PATH' : 'PATH='.$path);
    $files->deleteDirectory($root);
}
check(array_diff(glob(sys_get_temp_dir().'/metator-*') ?: [], $before) === [], 'Temporary files leaked');
echo "Remote staging checks passed.\n";
