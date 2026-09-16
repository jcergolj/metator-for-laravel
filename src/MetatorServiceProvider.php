<?php

namespace Jcergolj\MetatorForLaravel;

use Illuminate\Support\ServiceProvider;
use Jcergolj\MetatorForLaravel\Commands\InstallDeployerScaffoldingCommand;
use Jcergolj\MetatorForLaravel\Commands\PrepareServerCommand;
use Jcergolj\MetatorForLaravel\Commands\RunRemoteProvisioningCommand;

class MetatorServiceProvider extends ServiceProvider
{
    public function register(): void
    {
    }

    public function boot(): void
    {
        $this->publishes([
            dirname(__DIR__).'/stubs/scripts/steps' => base_path('metator/steps'),
        ], 'metator-steps');

        if ($this->app->runningInConsole()) {
            $this->commands([
                InstallDeployerScaffoldingCommand::class,
                PrepareServerCommand::class,
                RunRemoteProvisioningCommand::class,
            ]);
        }
    }
}
