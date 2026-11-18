<?php

declare(strict_types=1);

namespace Jcergolj\MetatorForLaravel\Commands;

use Illuminate\Filesystem\Filesystem;

use function Laravel\Prompts\confirm;
use function Laravel\Prompts\multiselect;
use function Laravel\Prompts\table;

class InstallationAnswers
{
    private array $answers = [];

    private array $changes = [];

    private string $draftPath;

    private string $secretPath;

    private const LABELS = [
        'repository' => 'GitHub repository (owner/repository)',
        'site_id' => 'Site ID',
        'steps' => 'Deployment steps',
        'worker' => 'Worker mode',
        'redis' => 'Redis capability',
        'scheduler' => 'Enable the scheduler?',
        'cloudflare_token' => 'Cloudflare API token',
        'cloudflare_zone' => 'Cloudflare zone ID',
        'branch' => 'Deployment branch',
        'host' => 'Server IP address',
        'ssh_user' => 'Operator SSH user',
        'domain' => 'Production domain',
        'database' => 'Database driver',
        'php_version' => 'PHP version',
    ];

    public function __construct(private Filesystem $files)
    {
    }

    public function load(string $basePath, string $name): void
    {
        $this->draftPath = $basePath.'/.metator.'.$name.'.answers.json';
        $this->secretPath = $basePath.'/metator.'.$name.'.local.php';
        $draft = $this->files->exists($this->draftPath)
            ? json_decode($this->files->get($this->draftPath), true, flags: JSON_THROW_ON_ERROR)
            : [];
        $this->answers = [];
        $this->changes = [];
        $sitePath = $basePath.'/metator.'.$name.'.php';
        if ($this->files->exists($sitePath)) {
            $site = require $sitePath;
            $this->answers = array_replace([
                'repository' => $site['repository'],
                'site_id' => $site['site_id'],
                'worker' => $site['worker'],
                'redis' => $site['redis'],
                'scheduler' => $site['scheduler'],
                'host' => $site['ssh']['host'],
                'ssh_user' => $site['ssh']['user'],
                'domain' => $site['domain'],
                'database' => $site['database'] === 'mariadb' ? 'mysql' : 'sqlite',
                'php_version' => $site['php_version'],
            ], array_intersect_key($site, array_flip(['branch', 'steps'])));
            if (isset($this->answers['steps'])) {
                foreach (['node', 'cloudflare'] as $capability) {
                    $this->answers['steps'] = array_values(array_diff($this->answers['steps'], [$capability]));
                    if ($site[$capability] ?? false) {
                        $this->answers['steps'][] = $capability;
                    }
                }
            }
        }
        // A draft contains pending edits; successful installation removes it.
        $this->answers = array_replace($this->answers, $draft);
        if ($this->files->exists($this->secretPath)) {
            $secrets = require $this->secretPath;
            if (isset($secrets['cloudflare'])) {
                $this->answers['cloudflare_token'] = $secrets['cloudflare']['token'];
                if ($secrets['cloudflare']['zone_id'] !== '') {
                    $this->answers['cloudflare_zone'] = $secrets['cloudflare']['zone_id'];
                }
            }
        }
        if ($this->answers === []) {
            return;
        }

        $rows = [];
        foreach ($this->answers as $key => $value) {
            if (isset(self::LABELS[$key])) {
                $rows[] = [__(self::LABELS[$key]), $this->summaryValue($key, $value)];
            }
        }
        table([__('Setting'), __('Saved value')], $rows);
        if (! confirm(label: __('Reuse previous settings?'), default: true)) {
            $this->changes = multiselect(label: __('Settings to change'), options: array_map(function (string $label): string {
                return __($label);
            }, self::LABELS));
        }
    }

    public function ask(string $key, callable $prompt): mixed
    {
        if (array_key_exists($key, $this->answers) && ! in_array($key, $this->changes, true)) {
            return $this->answers[$key];
        }

        $this->answers[$key] = $prompt($this->answers[$key] ?? null);
        $this->save();

        return $this->answers[$key];
    }

    public function finish(string $basePath, string $name): void
    {
        $this->files->delete($basePath.'/.metator.'.$name.'.answers.json');
    }

    private function summaryValue(string $key, mixed $value): string
    {
        if ($key === 'cloudflare_token') {
            return __('Saved (hidden)');
        }
        if (is_array($value)) {
            return implode(', ', $value);
        }
        if (is_bool($value)) {
            return $value ? __('Yes') : __('No');
        }

        return $value;
    }

    private function save(): void
    {
        $basePath = dirname($this->draftPath);
        $ignorePath = $basePath.'/.gitignore';
        $ignore = $this->files->exists($ignorePath) ? $this->files->get($ignorePath) : '';
        foreach (['/.metator.*.answers.json', '/metator.*.local.php'] as $pattern) {
            if (! in_array($pattern, explode("\n", $ignore), true)) {
                $ignore = rtrim($ignore)."\n".$pattern."\n";
            }
        }
        $this->files->put($ignorePath, $ignore);
        $draft = array_diff_key($this->answers, array_flip(['cloudflare_token', 'cloudflare_zone']));
        $this->files->replace($this->draftPath, json_encode($draft, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR).PHP_EOL, 0600);

        if (isset($this->answers['cloudflare_token'])) {
            $secrets = $this->files->exists($this->secretPath) ? require $this->secretPath : [];
            $secrets['cloudflare'] = [
                'token' => $this->answers['cloudflare_token'],
                'zone_id' => $this->answers['cloudflare_zone'] ?? '',
            ];
            $this->files->replace($this->secretPath, "<?php\n\nreturn ".var_export($secrets, true).";\n", 0600);
        }
    }
}
