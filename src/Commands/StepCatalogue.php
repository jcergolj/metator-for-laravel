<?php

declare(strict_types=1);

namespace Jcergolj\MetatorForLaravel\Commands;

use Illuminate\Filesystem\Filesystem;
use RuntimeException;
use SplFileInfo;

final class StepCatalogue
{
    public function __construct(private Filesystem $files)
    {
    }

    public function publish(string $source, string $target, string $manifest, bool $force): void
    {
        $this->files->ensureDirectoryExists($target);
        $packageFiles = $this->files->files($source);
        $knownPackageFiles = $this->files->exists($manifest)
            ? json_decode($this->files->get($manifest), true, flags: JSON_THROW_ON_ERROR)
            : [];

        foreach ($packageFiles as $file) {
            $destination = $target.'/'.$file->getFilename();
            if (! $this->files->exists($destination) || ($force && in_array($file->getFilename(), $knownPackageFiles, true))) {
                $this->files->copy($file->getPathname(), $destination);
            }
        }

        $this->files->put($manifest, json_encode(
            array_values(array_unique(array_merge($knownPackageFiles, array_map(
                fn (SplFileInfo $file): string => $file->getFilename(),
                $packageFiles,
            )))),
            JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR,
        ).PHP_EOL);
    }

    /** @return list<array{id: string, title: string, group: string, required: bool, default: bool, order: int, file: string}> */
    public function available(string $directory): array
    {
        $steps = [];
        $normalizedIds = [];
        foreach ($this->files->files($directory) as $file) {
            if ($file->getExtension() !== 'sh' || str_starts_with($file->getFilename(), '.')) {
                continue;
            }

            $contents = $this->files->get($file->getPathname());
            $metadata = [];
            foreach (['id', 'title', 'group', 'required', 'default', 'order'] as $key) {
                if (preg_match('/^# @'.preg_quote($key, '/').':[ \t]*(.+)$/m', $contents, $match) === 1) {
                    $metadata[$key] = trim($match[1]);
                }
            }
            foreach (['id', 'title', 'group', 'required', 'default', 'order'] as $key) {
                if (! isset($metadata[$key])) {
                    throw new RuntimeException("Step {$file->getFilename()} is missing @{$key} metadata.");
                }
            }
            if (preg_match('/^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/', $metadata['id']) !== 1) {
                throw new RuntimeException("Step {$file->getFilename()} has invalid @id: {$metadata['id']}.");
            }
            if ($metadata['title'] === '' || $metadata['group'] === '') {
                throw new RuntimeException("Step {$file->getFilename()} has an empty @title or @group.");
            }
            foreach (['required', 'default'] as $boolean) {
                if (! in_array($metadata[$boolean], ['true', 'false'], true)) {
                    throw new RuntimeException("Step {$file->getFilename()} has invalid @{$boolean}: {$metadata[$boolean]}.");
                }
            }
            if (preg_match('/^(?:0|[1-9][0-9]*)$/', $metadata['order']) !== 1) {
                throw new RuntimeException("Step {$file->getFilename()} has invalid @order: {$metadata['order']}.");
            }
            $normalizedId = str_replace('-', '_', $metadata['id']);
            if (isset($normalizedIds[$normalizedId])) {
                throw new RuntimeException("Steps {$normalizedIds[$normalizedId]} and {$file->getFilename()} collide as {$normalizedId}().");
            }
            $normalizedIds[$normalizedId] = $file->getFilename();
            $steps[] = [
                'id' => $metadata['id'],
                'title' => $metadata['title'],
                'group' => $metadata['group'],
                'required' => $metadata['required'] === 'true',
                'default' => $metadata['default'] === 'true',
                'order' => (int) $metadata['order'],
                'file' => $file->getFilename(),
            ];
            $function = 'step_'.str_replace('-', '_', $metadata['id']);
            if (preg_match('/(?:^|[;\s])(?:function\s+)?'.preg_quote($function, '/').'\s*\(\)\s*\{/', $contents) !== 1) {
                throw new RuntimeException("Step {$file->getFilename()} must define {$function}().");
            }
        }

        usort($steps, fn (array $left, array $right): int => [$left['order'], str_replace('-', '_', $left['id']), $left['file']]
            <=> [$right['order'], str_replace('-', '_', $right['id']), $right['file']]);

        return $steps;
    }

    public function validateSelection(array $availableSteps, array $selectedSteps): void
    {
        $mandatory = ['prerequisites', 'shared-env', 'database', 'github-key', 'permissions', 'deployer-instructions'];
        foreach ($availableSteps as $step) {
            if (($step['required'] || in_array($step['id'], $mandatory, true))
                && ! in_array($step['id'], array_column($selectedSteps, 'id'), true)) {
                throw new RuntimeException("Required step is not selected: {$step['id']}.");
            }
        }

        $groups = [];
        foreach ($selectedSteps as $step) {
            if ($step['group'] !== 'none') {
                $groups[$step['group']][] = $step['id'];
            }
        }
        foreach ($groups as $group => $steps) {
            if (count($steps) > 1) {
                throw new RuntimeException("Select only one step from the {$group} group.");
            }
        }
    }
}
