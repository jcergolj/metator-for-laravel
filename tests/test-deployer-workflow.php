<?php

declare(strict_types=1);

$root = dirname(__DIR__);
$deployer = getenv('METATOR_TEST_DEPLOYER') ?: $root.'/vendor/bin/dep';
if (! is_executable($deployer)) {
    fwrite(STDERR, "Install Composer dependencies before running this test.\n");
    exit(1);
}

$directory = sys_get_temp_dir().'/metator-deployer-proof-'.bin2hex(random_bytes(8));
mkdir($directory, 0700, true);

try {
    foreach (['8.4', '8.5'] as $phpVersion) {
        foreach (['sqlite', 'mariadb'] as $database) {
            foreach (['none', 'queue', 'horizon'] as $worker) {
                $siteId = 'proof-'.str_replace('.', '', $phpVersion).'-'.$database.'-'.$worker;
                $site = [
                    'site_id' => $siteId,
                    'php_version' => $phpVersion,
                    'worker' => $worker,
                    'ssh' => ['host' => '127.0.0.1', 'user' => 'operator'],
                    'deploy_user' => 'deployer',
                    'repository' => 'example/application',
                    'database' => $database,
                ];
                file_put_contents($directory.'/site.php', '<?php return '.var_export($site, true).';'.PHP_EOL);

                $recipe = file_get_contents($root.'/stubs/deploy.php.stub');
                if ($recipe === false) {
                    throw new RuntimeException('Could not read the Deployer recipe stub.');
                }
                $recipe = str_replace(['__CONFIG_FILE__', '__BRANCH__'], ['site.php', 'main'], $recipe);
                file_put_contents($directory.'/deploy.php', $recipe);
                file_put_contents($directory.'/deploy.php', <<<'PHP'

task('acceptance:assert-site-settings', function (): void {
    $site = require __DIR__.'/site.php';
    $expectedRepository = 'git-'.$site['site_id'].':'.$site['repository'].'.git';
    $sqliteFileIsShared = in_array('database/database.sqlite', get('shared_files', []), true);

    if (get('application') !== $site['site_id']
        || get('repository') !== $expectedRepository
        || get('deploy_path') !== '/var/www/'.$site['site_id']
        || get('bin/php') !== '/usr/bin/php'.$site['php_version']
        || get('worker_type') !== $site['worker']
        || $sqliteFileIsShared !== ($site['database'] === 'sqlite')) {
        throw new RuntimeException('Generated Deployer configuration does not match the selected site settings.');
    }
});
PHP
                    , FILE_APPEND);

                $output = [];
                exec(escapeshellarg($deployer).' acceptance:assert-site-settings --file='.escapeshellarg($directory.'/deploy.php').' --no-interaction 2>&1', $output, $status);
                if ($status !== 0) {
                    throw new RuntimeException(implode(PHP_EOL, $output));
                }

                $output = [];
                exec(escapeshellarg($deployer).' tree deploy --file='.escapeshellarg($directory.'/deploy.php').' 2>&1', $output, $status);
                if ($status !== 0) {
                    throw new RuntimeException(implode(PHP_EOL, $output));
                }

                $tree = implode(PHP_EOL, $output);
                foreach (['metator:verify-runtime', 'deploy:prepare', 'deploy:vendors', 'artisan:migrate', 'deploy:cache', 'deploy:symlink'] as $requiredTask) {
                    if (! str_contains($tree, $requiredTask)) {
                        throw new RuntimeException("Deployer 8.0.5 task tree is missing {$requiredTask} for PHP {$phpVersion}, {$database}, {$worker}.");
                    }
                }
                if ($worker === 'none' && str_contains($tree, 'deploy:activate-workers')) {
                    throw new RuntimeException("Worker lifecycle tasks must be absent for PHP {$phpVersion}, {$database} when workers are disabled.");
                }
                if ($worker !== 'none' && (! str_contains($tree, 'deploy:activate-workers') || ! str_contains($tree, 'deploy:verify-workers'))) {
                    throw new RuntimeException("Worker lifecycle hooks are missing for PHP {$phpVersion}, {$database}, {$worker}.");
                }
                if (str_contains($tree, 'metator:provision') || str_contains($tree, 'metator:prepare-server')) {
                    throw new RuntimeException("Deployment task tree triggered provisioning or shared preparation for PHP {$phpVersion}, {$database}, {$worker}.");
                }
                $loadedSite = require $directory.'/site.php';
                if (($loadedSite['php_version'] ?? null) !== $phpVersion || ($loadedSite['database'] ?? null) !== $database
                    || ($loadedSite['worker'] ?? null) !== $worker || ($loadedSite['site_id'] ?? null) !== $siteId) {
                    throw new RuntimeException("Selected site settings changed while loading PHP {$phpVersion}, {$database}, {$worker}.");
                }
            }
        }
    }
} finally {
    foreach (glob($directory.'/*') ?: [] as $file) {
        unlink($file);
    }
    rmdir($directory);
}

fwrite(STDOUT, "Generated Deployer workflows load for PHP, database, and worker selections.\n");
