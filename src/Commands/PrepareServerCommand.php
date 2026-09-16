<?php

declare(strict_types=1);

namespace Jcergolj\MetatorForLaravel\Commands;

class PrepareServerCommand extends RunRemoteProvisioningCommand
{
    protected $signature = 'metator:prepare-server {--config= : The site configuration file}';

    protected $description = 'Prepare shared server capabilities for one selected site';

    public function handle(): int
    {
        return $this->runOperation('prepare-server');
    }
}
