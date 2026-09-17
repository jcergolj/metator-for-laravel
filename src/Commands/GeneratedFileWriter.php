<?php

declare(strict_types=1);

namespace Jcergolj\MetatorForLaravel\Commands;

use Illuminate\Filesystem\Filesystem;
use RuntimeException;

final class GeneratedFileWriter
{
    public function __construct(private Filesystem $files)
    {
    }

    public function write(array $installation, string $stubRoot, string $basePath, string $stepCatalogue, bool $force, callable $info, callable $warn): void
    {
        $placeholders = $installation['placeholders'];
        $selectedStepIds = array_column($installation['selected_steps'], 'id');
        $siteConfiguration = $installation['site_configuration'];

        $this->files->put($siteConfiguration, "<?php\n\nreturn ".var_export([
            'site_id' => $placeholders['__SITE_ID__'],
            'ssh' => ['host' => $placeholders['__SERVER_IP__'], 'user' => $placeholders['__SSH_USER__']],
            'deploy_user' => 'deployer',
            'domain' => $placeholders['__DOMAIN__'],
            'repository' => $placeholders['__GITHUB_REPOSITORY__'],
            'php_version' => $placeholders['__PHP_VERSION__'],
            'database' => $placeholders['__DATABASE_DRIVER__'] === 'mysql' ? 'mariadb' : 'sqlite',
            'cloudflare' => in_array('cloudflare', $selectedStepIds, true),
            'redis' => $placeholders['__REDIS_CAPABILITY__'],
            'worker' => $placeholders['__WORKER_TYPE__'],
            'scheduler' => $placeholders['__USE_SCHEDULER__'] === 'true',
        ], true).";\n");

        if ($installation['cloudflare_secrets'] !== null) {
            $secretConfiguration = $installation['secret_configuration'];
            $this->files->put($secretConfiguration, "<?php\n\nreturn ".var_export(['cloudflare' => $installation['cloudflare_secrets']], true).";\n");
            @chmod($secretConfiguration, 0600);
            $warn("Cloudflare credentials stored locally in {$secretConfiguration}; keep this file out of version control.");
        } elseif ($force && $this->files->exists($installation['secret_configuration'])) {
            $this->files->delete($installation['secret_configuration']);
        }
        $info("Configured site: {$siteConfiguration}");

        foreach ([
            'deploy.php.stub' => $basePath.'/deploy.php',
            'scripts/server-bootstrap.sh' => $basePath.'/scripts/server-bootstrap.sh',
            'scripts/environment-update.sh' => $basePath.'/scripts/environment-update.sh',
            'scripts/lib/common.sh' => $basePath.'/scripts/lib/common.sh',
            'scripts/steps/10-deployer-instructions.sh' => $basePath.'/scripts/steps/10-deployer-instructions.sh',
        ] as $stub => $target) {
            $this->copy($stubRoot.'/'.$stub, $target, $placeholders, $force, $info, $warn);
        }
        $this->writeSelectedSteps($installation['selected_steps'], $stepCatalogue, $basePath.'/scripts/steps', $placeholders, $force, $info, $warn);
        $this->copy($installation['env_example'], $basePath.'/scripts/.env.example', $placeholders, $force, $info, $warn);
    }

    private function writeSelectedSteps(array $selectedSteps, string $source, string $target, array $placeholders, bool $force, callable $info, callable $warn): void
    {
        $manifest = dirname($target).'/.metator-manifest.json';
        if ($this->files->exists($manifest) && ! $force) {
            $warn("Skipped existing generated steps: {$target}");
            return;
        }
        $oldFiles = $this->files->exists($manifest) ? json_decode($this->files->get($manifest), true, flags: JSON_THROW_ON_ERROR) : [];
        foreach ($oldFiles as $file) {
            $this->files->delete($target.'/'.$file);
        }
        foreach ($selectedSteps as $step) {
            $this->copy($source.'/'.$step['file'], $target.'/'.$step['file'], $placeholders, $force, $info, $warn);
        }
        $this->files->put($manifest, json_encode(array_column($selectedSteps, 'file'), JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR).PHP_EOL);
    }

    private function copy(string $source, string $target, array $placeholders, bool $force, callable $info, callable $warn): void
    {
        if (! $this->files->exists($source)) {
            throw new RuntimeException("Missing stub file: {$source}");
        }
        if ($this->files->exists($target) && ! $force) {
            $warn("Skipped existing file: {$target}");
            return;
        }
        $this->files->ensureDirectoryExists(dirname($target));
        $this->files->put($target, str_replace(array_keys($placeholders), array_values($placeholders), $this->files->get($source)));
        if (str_ends_with($target, '.sh')) {
            @chmod($target, 0755);
        }
        $info("Installed: {$target}");
    }
}
