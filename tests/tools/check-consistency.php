<?php

declare(strict_types=1);

/**
 * Vérification minimale de cohérence d'un projet PHP.
 *
 * Usage:
 *   php tools/check-consistency.php
 */

$root = dirname(__DIR__);
$src = $root . '/src';

$errors = [];
$warnings = [];
$classes = [];

/**
 * Recherche récursivement les fichiers PHP.
 */
function phpFiles(string $directory): array
{
    if (! is_dir($directory)) {
        return [];
    }

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator(
            $directory,
            FilesystemIterator::SKIP_DOTS
        )
    );

    $files = [];

    foreach ($iterator as $file) {
        if ($file->isFile() && $file->getExtension() === 'php') {
            $files[] = $file->getPathname();
        }
    }

    sort($files);

    return $files;
}

/**
 * Convertit un chemin de fichier en classe PSR-4 attendue.
 */
function expectedClass(string $file, string $src): ?string
{
    $relative = str_replace('\\', '/', substr($file, strlen($src) + 1));

    if (! str_ends_with($relative, '.php')) {
        return null;
    }

    $relative = substr($relative, 0, -4);

    return 'YourVendor\\YourPackage\\' . str_replace('/', '\\', $relative);
}

/**
 * Analyse les classes déclarées dans un fichier.
 */
function declaredClasses(string $file): array
{
    $code = file_get_contents($file);

    if ($code === false) {
        return [];
    }

    $tokens = token_get_all($code);

    $namespace = '';
    $classes = [];

    $count = count($tokens);

    for ($i = 0; $i < $count; $i++) {
        $token = $tokens[$i];

        if (! is_array($token)) {
            continue;
        }

        if ($token[0] === T_NAMESPACE) {
            $namespace = '';

            for ($j = $i + 1; $j < $count; $j++) {
                $part = $tokens[$j];

                if (is_array($part) && in_array($part[0], [T_STRING, T_NAME_QUALIFIED])) {
                    $namespace .= $part[1];

                    continue;
                }

                if ($part === '\\') {
                    $namespace .= '\\';

                    continue;
                }

                break;
            }

            $namespace = trim($namespace, '\\');
        }

        if (
            $token[0] === T_CLASS ||
            $token[0] === T_INTERFACE ||
            $token[0] === T_TRAIT ||
            (defined('T_ENUM') && $token[0] === T_ENUM)
        ) {
            // Ignore anonymous classes.
            $j = $i + 1;

            while ($j < $count && is_array($tokens[$j]) && $tokens[$j][0] === T_WHITESPACE) {
                $j++;
            }

            if (! isset($tokens[$j]) || ! is_array($tokens[$j]) || $tokens[$j][0] !== T_STRING) {
                continue;
            }

            $name = $tokens[$j][1];

            $classes[] = $namespace
                ? $namespace . '\\' . $name
                : $name;
        }
    }

    return $classes;
}

echo PHP_EOL;
echo "==========================================" . PHP_EOL;
echo " PHP Project Consistency Check" . PHP_EOL;
echo "==========================================" . PHP_EOL . PHP_EOL;

if (! is_dir($src)) {
    echo "❌ Dossier src/ introuvable." . PHP_EOL;
    exit(1);
}

$files = phpFiles($src);

echo "Fichiers PHP trouvés : " . count($files) . PHP_EOL . PHP_EOL;

/*
|--------------------------------------------------------------------------
| 1. Vérification de syntaxe
|--------------------------------------------------------------------------
*/

echo "[1/4] Vérification de la syntaxe..." . PHP_EOL;

foreach ($files as $file) {
    $command = sprintf(
        '%s -l %s 2>&1',
        escapeshellarg(PHP_BINARY),
        escapeshellarg($file)
    );

    exec($command, $output, $exitCode);

    if ($exitCode !== 0) {
        $errors[] = "Erreur de syntaxe : " . $file;

        foreach ($output as $line) {
            $errors[] = "  " . $line;
        }
    }

    $output = [];
}

echo $errors
    ? "❌ Erreurs trouvées." . PHP_EOL
    : "✅ Syntaxe correcte." . PHP_EOL;

echo PHP_EOL;

/*
|--------------------------------------------------------------------------
| 2. Détection des classes
|--------------------------------------------------------------------------
*/

echo "[2/4] Analyse des classes..." . PHP_EOL;

foreach ($files as $file) {
    $declared = declaredClasses($file);

    foreach ($declared as $class) {
        if (isset($classes[$class])) {
            $errors[] = sprintf(
                "Classe dupliquée : %s (%s et %s)",
                $class,
                $classes[$class],
                $file
            );

            continue;
        }

        $classes[$class] = $file;
    }
}

echo "Classes trouvées : " . count($classes) . PHP_EOL;

echo $errors
    ? "❌ Problèmes détectés." . PHP_EOL
    : "✅ Pas de doublon détecté." . PHP_EOL;

echo PHP_EOL;

/*
|--------------------------------------------------------------------------
| 3. Vérification PSR-4
|--------------------------------------------------------------------------
*/

echo "[3/4] Vérification PSR-4..." . PHP_EOL;

/*
 * Adapter ce namespace à ton composer.json.
 */
$baseNamespace = 'YourVendor\\YourPackage\\';

foreach ($classes as $class => $file) {
    $relative = str_replace('\\', '/', substr($file, strlen($src) + 1));
    $relative = substr($relative, 0, -4);

    $expected = $baseNamespace . str_replace('/', '\\', $relative);

    if ($class !== $expected) {
        $errors[] = sprintf(
            "PSR-4 incohérent : %s\n  Fichier : %s\n  Attendu : %s",
            $class,
            $file,
            $expected
        );
    }
}

echo $errors
    ? "❌ Incohérences PSR-4 détectées." . PHP_EOL
    : "✅ Structure PSR-4 cohérente." . PHP_EOL;

echo PHP_EOL;

/*
|--------------------------------------------------------------------------
| 4. Vérification du nom fichier / classe
|--------------------------------------------------------------------------
*/

echo "[4/4] Vérification fichier ↔ classe..." . PHP_EOL;

foreach ($classes as $class => $file) {
    $shortName = substr($class, strrpos($class, '\\') + 1);

    $filename = pathinfo($file, PATHINFO_FILENAME);

    if ($shortName !== $filename) {
        $warnings[] = sprintf(
            "Nom fichier différent : %s contient %s",
            basename($file),
            $class
        );
    }
}

echo $warnings
    ? "⚠️ Avertissements détectés." . PHP_EOL
    : "✅ Noms cohérents." . PHP_EOL;

echo PHP_EOL;

/*
|--------------------------------------------------------------------------
| Résultat
|--------------------------------------------------------------------------
*/

echo "==========================================" . PHP_EOL;
echo " Résultat" . PHP_EOL;
echo "==========================================" . PHP_EOL;

if ($errors) {
    echo PHP_EOL;
    echo "❌ " . count($errors) . " erreur(s)" . PHP_EOL . PHP_EOL;

    foreach ($errors as $error) {
        echo "- " . $error . PHP_EOL;
    }
}

if ($warnings) {
    echo PHP_EOL;
    echo "⚠️ " . count($warnings) . " avertissement(s)" . PHP_EOL . PHP_EOL;

    foreach ($warnings as $warning) {
        echo "- " . $warning . PHP_EOL;
    }
}

if (! $errors && ! $warnings) {
    echo PHP_EOL;
    echo "🎉 Projet cohérent !" . PHP_EOL;
}

echo PHP_EOL;

exit($errors ? 1 : 0);
