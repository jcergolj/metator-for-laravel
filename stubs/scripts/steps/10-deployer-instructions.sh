#!/usr/bin/env bash

step_deployer_instructions() {
    echo
    echo 'Required deployer.php changes:'
    echo "  Set the production hostname to: $SERVER_IP"
    if [[ "$USE_SCHEDULER" == true ]]; then
        echo '  Scheduler: no deployer.php hook is required; the server cron uses current.'
        echo '  Scheduler server setup: scripts/setup.sh creates the cron entry for www-data.'
    else
        echo '  Scheduler: leave the scheduler cron hook out.'
    fi
    if [[ "$USE_QUEUE" == true ]]; then
        echo
        if [[ "$USE_HORIZON" == true ]]; then
            echo '  Horizon: add this task and hook:'
            echo '  Horizon server setup: scripts/setup.sh installs Redis and writes the Supervisor program.'
            echo "    task('deploy:horizon', function () {"
            echo "        run('cd {{release_path}} && {{bin/php}} artisan horizon:terminate');"
            echo '    });'
            echo "    after('deploy:symlink', 'deploy:horizon');"
        else
            echo '  Queue workers: add this hook after deploy:symlink:'
            echo '  Queue worker server setup: scripts/setup.sh writes the Supervisor queue:work program.'
            echo "    after('deploy:symlink', 'artisan:queue:restart');"
        fi
    fi
    if [[ "$USE_QUEUE" != true ]]; then
        echo '  Queue jobs: no queue worker or Horizon hooks are required.'
    fi
    echo "  Keep this failure hook: after('deploy:failed', 'deploy:unlock');"

    echo
    echo 'How to deploy from your local project:'
    echo '  1. Review deploy.php in the project root.'
    echo "  2. Set repository to: ${GITHUB_URL}"
    echo "  3. Set hostname to: ${SERVER_IP}"
    echo "  4. Set remoteUser to: ${DEPLOY_USER}"
    echo "  5. Set deployPath to: ${APP_FOLDER}"
    echo '  6. Test SSH access from your local machine:'
    echo "       ssh ${DEPLOY_USER}@${SERVER_IP}"
    echo '  7. Run the first deployment from your Laravel project root:'
    echo '       vendor/bin/dep deploy production'
    echo '  8. For later releases, run the same deploy command again.'
}
