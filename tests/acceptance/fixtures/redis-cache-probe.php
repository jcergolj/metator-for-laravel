<?php

declare(strict_types=1);

use Illuminate\Contracts\Console\Kernel;
use Illuminate\Queue\CallQueuedClosure;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Queue;

if ($argc < 3) {
    fwrite(STDERR, "Usage: redis-cache-probe.php <put|get|has> <key> [value]\n");
    exit(2);
}

require getcwd().'/vendor/autoload.php';
$app = require getcwd().'/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$operation = $argv[1];
$key = $argv[2];
if ($operation === 'put' && isset($argv[3])) {
    Cache::put($key, $argv[3], 600);
    exit(0);
}
if ($operation === 'get') {
    $value = Cache::get($key);
    if (is_string($value)) {
        fwrite(STDOUT, $value.PHP_EOL);
        exit(0);
    }
    exit(1);
}
if ($operation === 'has') {
    fwrite(STDOUT, Cache::has($key) ? "present\n" : "missing\n");
    exit(0);
}
if ($operation === 'queue-put') {
    Queue::later(now()->addMinutes(30), CallQueuedClosure::create(static fn (): null => null), [], 'default');
    fwrite(STDOUT, (string) Queue::size('default').PHP_EOL);
    exit(0);
}
if ($operation === 'queue-size') {
    fwrite(STDOUT, (string) Queue::size('default').PHP_EOL);
    exit(0);
}
if ($operation === 'session-put' && isset($argv[3])) {
    $session = app('session')->driver();
    $session->start();
    $session->put($key, $argv[3]);
    $session->save();
    fwrite(STDOUT, $session->getId().PHP_EOL);
    exit(0);
}
if ($operation === 'session-get' && isset($argv[3])) {
    $session = app('session')->driver();
    $session->setId($argv[3]);
    $session->start();
    $value = $session->get($key);
    if (is_string($value)) {
        fwrite(STDOUT, $value.PHP_EOL);
        exit(0);
    }
    exit(1);
}

fwrite(STDERR, "Unsupported cache operation or missing value\n");
exit(2);
