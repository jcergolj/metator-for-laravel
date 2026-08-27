<?php

namespace Deployer;

require 'recipe/laravel.php';

set('application', 'secamb');

set(
    'repository',
    'git@github-deployer:jcergolj/secamb.git'
);

set('branch', 'master');
set('keep_releases', 5);

host('production')
    ->setHostname('188.245.170.110')
    ->setRemoteUser('deployer')
    ->setDeployPath('/var/www/secamb');

add('shared_files', [
    'database/database.sqlite',
    'database/esr.sqlite',
]);

/*
 * Build Tailwind and optimize Importmap inside the new release before it
 * becomes publicly accessible.
 */
desc('Build frontend assets');
task('deploy:assets', function () {
    run('cd {{release_path}} && php artisan tailwindcss:download --force');
    run('cd {{release_path}} && {{bin/php}} artisan tailwindcss:build');
    run('cd {{release_path}} && {{bin/php}} artisan importmap:optimize');
});

after('deploy:vendors', 'deploy:assets');

task('deploy:cache', function () {
    run('cd {{release_path}} && php artisan optimize');
});

task('deploy:horizon', function () {
    run('cd {{release_path}} && php artisan horizon:terminate');
});

after('artisan:migrate', 'deploy:cache');

after('deploy:symlink', 'deploy:horizon');

after('deploy:failed', 'deploy:unlock');
