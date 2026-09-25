<?php

declare(strict_types=1);

$root = dirname(__DIR__);
$deployer = $root.'/vendor/bin/dep';
if (! is_executable($deployer)) {
    fwrite(STDERR, "Install Composer dependencies before running this test.\n");
    exit(1);
}

$directory = sys_get_temp_dir().'/metator-deployer-proof-'.bin2hex(random_bytes(8));
mkdir($directory, 0700, true);

try {
    foreach (['none', 'queue', 'horizon'] as $worker) {
        $site = [
            'site_id' => 'proof-site',
            'php_version' => '8.4',
            'worker' => $worker,
            'ssh' => ['host' => '127.0.0.1', 'user' => 'operator'],
            'deploy_user' => 'deployer',
            'repository' => 'example/application',
            'database' => 'sqlite',
        ];
        file_put_contents($directory.'/site.php', '<?php return '.var_export($site, true).';'.PHP_EOL);

        $recipe = file_get_contents($root.'/stubs/deploy.php.stub');
        if ($recipe === false) {
            throw new RuntimeException('Could not read the Deployer recipe stub.');
        }
        $recipe = str_replace(['__CONFIG_FILE__', '__BRANCH__'], ['site.php', 'main'], $recipe);
        file_put_contents($directory.'/deploy.php', $recipe);

        $output = [];
        exec(escapeshellarg($deployer).' tree deploy --file='.escapeshellarg($directory.'/deploy.php').' 2>&1', $output, $status);
        if ($status !== 0) {
            throw new RuntimeException(implode(PHP_EOL, $output));
        }

        $tree = implode(PHP_EOL, $output);
        foreach (['metator:verify-runtime', 'deploy:prepare', 'deploy:vendors', 'deploy:symlink'] as $requiredTask) {
            if (! str_contains($tree, $requiredTask)) {
                throw new RuntimeException("Deployer 8.0.5 task tree is missing {$requiredTask} for worker mode {$worker}.");
            }
        }
        if ($worker === 'none' && str_contains($tree, 'deploy:activate-workers')) {
            throw new RuntimeException('Worker lifecycle tasks must be absent when workers are disabled.');
        }
        if ($worker !== 'none' && (! str_contains($tree, 'deploy:activate-workers') || ! str_contains($tree, 'deploy:verify-workers'))) {
            throw new RuntimeException("Worker lifecycle hooks are missing for {$worker} mode.");
        }
        if (str_contains($tree, 'metator:provision') || str_contains($tree, 'metator:prepare-server')) {
            throw new RuntimeException('Deployment task tree must not trigger provisioning or shared preparation.');
        }
    }
} finally {
    foreach (glob($directory.'/*') ?: [] as $file) {
        unlink($file);
    }
    rmdir($directory);
}

fwrite(STDOUT, "Generated Deployer workflows load and build task trees for all worker modes.\n");
