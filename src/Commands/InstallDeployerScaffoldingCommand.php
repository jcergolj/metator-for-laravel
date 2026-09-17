<?php

declare(strict_types=1);

namespace Jcergolj\MetatorForLaravel\Commands;

use Illuminate\Console\Command;
use Illuminate\Filesystem\Filesystem;
use RuntimeException;

final class InstallDeployerScaffoldingCommand extends Command
{
    protected $signature = 'metator:install {--force : Overwrite existing files}';

    protected $description = 'Install Deployer deployment scaffolding into the current Laravel application';

    public function __construct(
        private Filesystem $files,
        private StepCatalogue $stepCatalogue,
        private InstallationPrompts $prompts,
        private GeneratedFileWriter $writer,
    ) {
        parent::__construct();
    }

    public function handle(): int
    {
        $stubRoot = dirname(__DIR__, 2).'/stubs';
        $basePath = $this->laravel->basePath();
        $stepCataloguePath = $basePath.'/metator/steps';

        $this->stepCatalogue->publish(
            $stubRoot.'/scripts/steps',
            $stepCataloguePath,
            $stepCataloguePath.'/.metator-package-manifest.json',
            (bool) $this->option('force'),
        );
        $installation = $this->prompts->collect($basePath, $stepCataloguePath, $this->stepCatalogue, fn (string $message): mixed => $this->error($message));
        if ($installation === null || ! $this->assertInstallable($installation['site_configuration'], $installation['env_example'])) {
            return self::FAILURE;
        }

        $this->writer->write(
            $installation,
            $stubRoot,
            $basePath,
            $stepCataloguePath,
            (bool) $this->option('force'),
            fn (string $message): mixed => $this->info($message),
            fn (string $message): mixed => $this->warn($message),
        );

        $this->info('Metator scaffolding installed.');
        $this->line('Next steps:');
        $this->line('  1. Review deploy.php');
        $this->line("  2. Prepare the shared server baseline when needed: php artisan metator:prepare-server --config=metator.{$installation['config_name']}.php");
        $this->line("  3. Provision the site: php artisan metator:provision --config=metator.{$installation['config_name']}.php");
        $this->line('  4. Deploy separately after infrastructure readiness: vendor/bin/dep deploy production');

        return self::SUCCESS;
    }

    private function assertInstallable(string $siteConfiguration, string $envExample): bool
    {
        if ($this->files->exists($siteConfiguration) && ! $this->option('force')) {
            $this->error("Site configuration already exists: {$siteConfiguration}. Use --force to replace it.");

            return false;
        }
        if (! $this->files->exists($envExample)) {
            throw new RuntimeException("Missing application .env.example: {$envExample}");
        }

        return true;
    }
}
