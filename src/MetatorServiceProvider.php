<?php

namespace Jcergolj\MetatorForLaravel;

use Illuminate\Support\ServiceProvider;
use Jcergolj\MetatorForLaravel\Commands\InstallDeployerScaffoldingCommand;

class MetatorServiceProvider extends ServiceProvider
{
    public function register(): void
    {
    }

    public function boot(): void
    {
        if ($this->app->runningInConsole()) {
            $this->commands([
                InstallDeployerScaffoldingCommand::class,
            ]);
        }
    }
}
