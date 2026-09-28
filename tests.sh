#!/usr/bin/env sh

set -eu

echo "=============================================="
echo "  Installation DevOps / Crash Tests / K8s"
echo "=============================================="

ROOT="$(pwd)"

# ------------------------------------------------
# Vérification
# ------------------------------------------------

if [ ! -f "$ROOT/composer.json" ]; then
    echo "❌ composer.json introuvable."
    echo "Lance ce script depuis la racine du projet."
    exit 1
fi

echo "📁 Projet : $ROOT"

# ------------------------------------------------
# Création des dossiers
# ------------------------------------------------

echo "📂 Création des dossiers..."

mkdir -p \
    .github/workflows \
    docker/test \
    k8s \
    tests/Crash \
    tests/Integration \
    tests/Unit \
    tools

# ------------------------------------------------
# Helper : création uniquement si absent
# ------------------------------------------------

create_file() {
    FILE="$1"

    if [ -f "$FILE" ]; then
        echo "⚠️  Existe déjà : $FILE"
        return
    fi

    echo "➕ Création : $FILE"
    cat > "$FILE"
}

# ------------------------------------------------
# Consistency checker
# ------------------------------------------------

create_file tools/check-consistency.php <<'PHP'
<?php

declare(strict_types=1);

$root = dirname(__DIR__);
$src  = $root . '/src';

$errors = [];
$classes = [];

if (!is_dir($src)) {
    fwrite(STDERR, "src/ introuvable.\n");
    exit(1);
}

$iterator = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator(
        $src,
        FilesystemIterator::SKIP_DOTS
    )
);

foreach ($iterator as $file) {
    if (!$file->isFile() || $file->getExtension() !== 'php') {
        continue;
    }

    $path = $file->getPathname();

    $output = [];
    $exitCode = 0;

    exec(
        escapeshellarg(PHP_BINARY) .
        ' -l ' .
        escapeshellarg($path) .
        ' 2>&1',
        $output,
        $exitCode
    );

    if ($exitCode !== 0) {
        $errors[] = "Syntax error: {$path}";
    }

    $code = file_get_contents($path);

    if ($code === false) {
        continue;
    }

    $tokens = token_get_all($code);
    $namespace = '';

    foreach ($tokens as $token) {
        if (!is_array($token)) {
            continue;
        }

        if ($token[0] === T_NAMESPACE) {
            $namespace = '';
            continue;
        }

        if (
            $token[0] === T_CLASS ||
            $token[0] === T_INTERFACE ||
            $token[0] === T_TRAIT
        ) {
            continue;
        }
    }
}

if ($errors) {
    echo "❌ Consistency check failed.\n";

    foreach ($errors as $error) {
        echo " - {$error}\n";
    }

    exit(1);
}

echo "✅ Consistency check passed.\n";
PHP

# ------------------------------------------------
# Crash test runner
# ------------------------------------------------

create_file tools/crash-test.sh <<'SH'
#!/usr/bin/env sh

set -eu

echo "================================"
echo " Crash / Failure Tests"
echo "================================"

if [ ! -d "tests/Crash" ]; then
    echo "❌ tests/Crash introuvable."
    exit 1
fi

if [ ! -x "vendor/bin/phpunit" ]; then
    echo "❌ PHPUnit introuvable."
    echo "Lance : composer install"
    exit 1
fi

vendor/bin/phpunit tests/Crash

echo ""
echo "✅ Crash tests passed."
SH

chmod +x tools/crash-test.sh

# ------------------------------------------------
# Dockerfile
# ------------------------------------------------

create_file docker/test/Dockerfile <<'DOCKER'
FROM php:8.3-cli

RUN docker-php-ext-install curl

WORKDIR /app

COPY . .

RUN php -v
RUN php -l tools/check-consistency.php

CMD ["php", "-v"]
DOCKER

# ------------------------------------------------
# Kubernetes Namespace
# ------------------------------------------------

create_file k8s/namespace.yaml <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: openai-sdk-test
YAML

# ------------------------------------------------
# Kubernetes Secret
# ------------------------------------------------

create_file k8s/secret.yaml <<'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: openai-test
  namespace: openai-sdk-test
type: Opaque
stringData:
  api-key: "test-key"
YAML

# ------------------------------------------------
# Kubernetes Deployment
# ------------------------------------------------

create_file k8s/deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sdk-test
  namespace: openai-sdk-test

spec:
  replicas: 2

  selector:
    matchLabels:
      app: sdk-test

  template:
    metadata:
      labels:
        app: sdk-test

    spec:
      containers:
        - name: php
          image: openai-sdk:test
          imagePullPolicy: Never

          env:
            - name: OPENAI_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openai-test
                  key: api-key

          resources:
            requests:
              cpu: 100m
              memory: 64Mi

            limits:
              cpu: 500m
              memory: 256Mi

          command:
            - php
            - -S
            - 0.0.0.0:8080
            - -t
            - /app
YAML

# ------------------------------------------------
# Kubernetes Service
# ------------------------------------------------

create_file k8s/service.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: sdk-test
  namespace: openai-sdk-test

spec:
  selector:
    app: sdk-test

  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
YAML

# ------------------------------------------------
# GitHub Actions - CI
# ------------------------------------------------

create_file .github/workflows/ci.yml <<'YAML'
name: CI

on:
  push:
    branches:
      - main
      - develop

  pull_request:

jobs:
  php:
    name: PHP Checks

    runs-on: ubuntu-latest

    strategy:
      matrix:
        php:
          - "8.2"
          - "8.3"
          - "8.4"

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: ${{ matrix.php }}
          extensions: curl, json
          coverage: none

      - name: Validate Composer
        run: composer validate --strict

      - name: Install dependencies
        run: composer install --prefer-dist --no-progress --no-interaction

      - name: Autoload
        run: composer dump-autoload --optimize --strict-psr

      - name: Consistency
        run: composer check:consistency

      - name: Tests
        run: composer test
YAML

# ------------------------------------------------
# GitHub Actions - Crash Tests
# ------------------------------------------------

create_file .github/workflows/crash-tests.yml <<'YAML'
name: Crash Tests

on:
  pull_request:
  push:
    branches:
      - main

jobs:
  crash:
    name: Crash Tests

    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: "8.3"
          extensions: curl, json
          coverage: none

      - name: Install dependencies
        run: composer install --prefer-dist --no-progress --no-interaction

      - name: Run crash tests
        run: ./tools/crash-test.sh
YAML

# ------------------------------------------------
# GitHub Actions - Kubernetes
# ------------------------------------------------

create_file .github/workflows/kubernetes.yml <<'YAML'
name: Kubernetes Tests

on:
  pull_request:
  push:
    branches:
      - main

jobs:
  kubernetes:

    name: Kubernetes Resilience

    runs-on: ubuntu-latest

    steps:

      - name: Checkout
        uses: actions/checkout@v4

      - name: Start Kind
        uses: helm/kind-action@v1
        with:
          cluster_name: sdk-test

      - name: Build Docker image
        run: |
          docker build \
            -f docker/test/Dockerfile \
            -t openai-sdk:test .

      - name: Load image
        run: |
          kind load docker-image \
            openai-sdk:test \
            --name sdk-test

      - name: Create namespace
        run: |
          kubectl apply \
            -f k8s/namespace.yaml

      - name: Create secret
        run: |
          kubectl apply \
            -f k8s/secret.yaml

      - name: Deploy
        run: |
          kubectl apply \
            -f k8s/deployment.yaml \
            -f k8s/service.yaml

      - name: Wait
        run: |
          kubectl rollout status \
            deployment/sdk-test \
            -n openai-sdk-test \
            --timeout=120s

      - name: Check pods
        run: |
          kubectl get pods \
            -n openai-sdk-test

      - name: Crash recovery
        run: |
          kubectl delete pod \
            -l app=sdk-test \
            -n openai-sdk-test

      - name: Wait for recovery
        run: |
          sleep 5

          kubectl get pods \
            -n openai-sdk-test

      - name: Verify deployment
        run: |
          kubectl rollout status \
            deployment/sdk-test \
            -n openai-sdk-test \
            --timeout=120s

      - name: Logs on failure
        if: failure()
        run: |
          kubectl get pods \
            -n openai-sdk-test

          kubectl describe pods \
            -n openai-sdk-test

          kubectl logs \
            -l app=sdk-test \
            -n openai-sdk-test \
            --all-containers=true \
            --ignore-errors
YAML

# ------------------------------------------------
# Composer scripts
# ------------------------------------------------

echo ""
echo "🧩 Vérification de composer.json..."

if command -v php >/dev/null 2>&1; then

    php <<'PHP'
<?php

$file = 'composer.json';

$data = json_decode(
    file_get_contents($file),
    true,
    512,
    JSON_THROW_ON_ERROR
);

$data['scripts'] ??= [];

$data['scripts']['check:consistency']
    ??= 'php tools/check-consistency.php';

$data['scripts']['check:crash']
    ??= './tools/crash-test.sh';

$data['scripts']['check']
    ??= [
        '@check:consistency',
        '@check:crash',
        '@test'
    ];

file_put_contents(
    $file,
    json_encode(
        $data,
        JSON_PRETTY_PRINT |
        JSON_UNESCAPED_SLASHES
    ) . PHP_EOL
);

echo "✅ composer.json mis à jour.\n";
PHP

else
    echo "⚠️ PHP non installé : composer.json non modifié."
fi

# ------------------------------------------------
# Résumé
# ------------------------------------------------

echo ""
echo "=============================================="
echo " Installation terminée"
echo "=============================================="
echo ""
echo "Ajouté :"
echo "  .github/workflows/ci.yml"
echo "  .github/workflows/crash-tests.yml"
echo "  .github/workflows/kubernetes.yml"
echo "  docker/test/Dockerfile"
echo "  k8s/namespace.yaml"
echo "  k8s/secret.yaml"
echo "  k8s/deployment.yaml"
echo "  k8s/service.yaml"
echo "  tests/Crash/"
echo "  tools/check-consistency.php"
echo "  tools/crash-test.sh"
echo ""
echo "Commandes :"
echo ""
echo "  composer check"
echo "  composer check:consistency"
echo "  composer check:crash"
echo ""
echo "Pour les tests Kubernetes locaux :"
echo ""
echo "  kind create cluster --name sdk-test"
echo "  docker build -f docker/test/Dockerfile -t openai-sdk:test ."
echo "  kind load docker-image openai-sdk:test --name sdk-test"
echo "  kubectl apply -f k8s/"
echo ""
echo "✅ DevOps installé."