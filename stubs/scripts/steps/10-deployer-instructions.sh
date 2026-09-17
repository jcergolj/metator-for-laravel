#!/usr/bin/env bash
# @id: deployer-instructions
# @title: Print deployer instructions
# @group: none
# @required: true
# @default: true
# @order: 100

step_deployer_instructions() {
    echo
    echo 'The generated deploy.php reads the selected site configuration:'
    echo '  Site identity, repository, host, deploy user, path, and PHP version are not duplicated.'
    if [[ "$USE_SCHEDULER" == true ]]; then
        echo '  Scheduler: no deployer.php hook is required; the server cron uses current.'
        echo '  Scheduler server setup: scripts/server-bootstrap.sh creates the cron entry for www-data.'
    else
        echo '  Scheduler: leave the scheduler cron hook out.'
    fi
    if [[ "$USE_QUEUE" == true ]]; then
        echo
        if [[ "$USE_HORIZON" == true ]]; then
            echo '  Horizon: deploy.php already terminates Horizon after the new release is live.'
            echo '  Horizon server setup: scripts/server-bootstrap.sh installs Redis and writes the Supervisor program.'
        else
            echo '  Queue workers: deploy.php restarts queue workers after the new release is live.'
            echo '  Queue worker server setup: scripts/server-bootstrap.sh writes the Supervisor queue:work program.'
        fi
    fi
    if [[ "$USE_QUEUE" != true ]]; then
        echo '  Queue jobs: no queue worker or Horizon hooks are required.'
    fi
    echo "  Keep this failure hook: after('deploy:failed', 'deploy:unlock');"

    echo
    echo 'How to deploy from your local project:'
    echo '  1. Review deploy.php in the project root.'
    echo '  2. Prepare the shared server baseline when needed:'
    echo '       php artisan metator:prepare-server --config=__CONFIG_FILE__'
    echo '  3. Provision this site and wait for infrastructure readiness:'
    echo '       php artisan metator:provision --config=__CONFIG_FILE__'
    echo '  4. Run the first deployment from your Laravel project root:'
    echo '       vendor/bin/dep deploy production'
    echo '  5. For later releases, run the same deploy command again.'
}
