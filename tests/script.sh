#!/usr/bin/env bash

set -e

PROJECT_NAME="${1:-openai-php}"

echo "🚀 Création du projet : $PROJECT_NAME"

mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

echo "📁 Création des dossiers..."

mkdir -p \
    src/Exception \
    tests \
    examples

echo "📝 Création de composer.json..."

cat > composer.json <<'JSON'
{
    "name": "vendor/openai-php",
    "description": "A lightweight PHP client for the OpenAI API",
    "type": "library",
    "license": "MIT",
    "require": {
        "php": "^8.2",
        "ext-curl": "*",
        "ext-json": "*"
    },
    "require-dev": {
        "phpunit/phpunit": "^11.0"
    },
    "autoload": {
        "psr-4": {
            "OpenAI\\": "src/"
        }
    },
    "autoload-dev": {
        "psr-4": {
            "OpenAI\\Tests\\": "tests/"
        }
    },
    "scripts": {
        "test": "phpunit"
    }
}
JSON

echo "📝 Création de OpenAI.php..."

cat > src/OpenAI.php <<'PHP'
<?php

declare(strict_types=1);

namespace OpenAI;

final class OpenAI
{
    public static function client(?string $apiKey = null): Client
    {
        $apiKey ??= getenv('OPENAI_API_KEY');

        if (!$apiKey) {
            throw new \InvalidArgumentException(
                'OpenAI API key is missing.'
            );
        }

        return new Client($apiKey);
    }
}
PHP

echo "📝 Création de Client.php..."

cat > src/Client.php <<'PHP'
<?php

declare(strict_types=1);

namespace OpenAI;

use OpenAI\Exception\ApiException;

final class Client
{
    private string $baseUrl = 'https://api.openai.com/v1';

    public function __construct(
        private readonly string $apiKey,
    ) {
    }

    public function chat(array $parameters): Response
    {
        return $this->post('/chat/completions', $parameters);
    }

    private function post(string $endpoint, array $data): Response
    {
        $ch = curl_init($this->baseUrl . $endpoint);

        if ($ch === false) {
            throw new ApiException('Unable to initialize cURL.');
        }

        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer ' . $this->apiKey,
                'Content-Type: application/json',
            ],
            CURLOPT_POSTFIELDS => json_encode(
                $data,
                JSON_THROW_ON_ERROR
            ),
        ]);

        $body = curl_exec($ch);
        $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);

        if ($body === false) {
            $error = curl_error($ch);
            curl_close($ch);

            throw new ApiException($error);
        }

        curl_close($ch);

        $response = json_decode(
            $body,
            true,
            512,
            JSON_THROW_ON_ERROR
        );

        if ($status >= 400) {
            throw ApiException::fromResponse(
                $status,
                $response
            );
        }

        return new Response($response);
    }
}
PHP

echo "📝 Création de Response.php..."

cat > src/Response.php <<'PHP'
<?php

declare(strict_types=1);

namespace OpenAI;

final readonly class Response
{
    public function __construct(
        private array $data,
    ) {
    }

    public function content(): ?string
    {
        return $this->data['choices'][0]['message']['content'] ?? null;
    }

    public function id(): ?string
    {
        return $this->data['id'] ?? null;
    }

    public function model(): ?string
    {
        return $this->data['model'] ?? null;
    }

    public function usage(): array
    {
        return $this->data['usage'] ?? [];
    }

    public function toArray(): array
    {
        return $this->data;
    }
}
PHP

echo "📝 Création de ApiException.php..."

cat > src/Exception/ApiException.php <<'PHP'
<?php

declare(strict_types=1);

namespace OpenAI\Exception;

final class ApiException extends \RuntimeException
{
    public function __construct(
        string $message,
        private readonly int $statusCode = 0,
        private readonly array $response = [],
    ) {
        parent::__construct($message, $statusCode);
    }

    public static function fromResponse(
        int $statusCode,
        array $response,
    ): self {
        $message = $response['error']['message']
            ?? 'OpenAI API request failed.';

        return new self(
            $message,
            $statusCode,
            $response
        );
    }

    public function statusCode(): int
    {
        return $this->statusCode;
    }

    public function response(): array
    {
        return $this->response;
    }
}
PHP

echo "📝 Création de l'exemple..."

cat > examples/chat.php <<'PHP'
<?php

declare(strict_types=1);

require dirname(__DIR__) . '/vendor/autoload.php';

use OpenAI\OpenAI;

$client = OpenAI::client();

$response = $client->chat([
    'model' => 'gpt-4o-mini',
    'messages' => [
        [
            'role' => 'user',
            'content' => 'Hello!',
        ],
    ],
]);

echo $response->content() . PHP_EOL;
PHP

echo "📝 Création de .gitignore..."

cat > .gitignore <<'EOF'
/vendor/
/.phpunit.cache/
.env
.idea/
.DS_Store
EOF

echo "📝 Création du test..."

cat > tests/ClientTest.php <<'PHP'
<?php

declare(strict_types=1);

namespace OpenAI\Tests;

use PHPUnit\Framework\TestCase;

final class ClientTest extends TestCase
{
    public function testProjectLoads(): void
    {
        $this->assertTrue(true);
    }
}
PHP

echo "📝 Création de phpunit.xml..."

cat > phpunit.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>

<phpunit
    bootstrap="vendor/autoload.php"
    colors="true"
>
    <testsuites>
        <testsuite name="OpenAI PHP">
            <directory>tests</directory>
        </testsuite>
    </testsuites>
</phpunit>
XML

echo "📝 Création du README..."

cat > README.md <<'MD'
# OpenAI PHP

A lightweight PHP client for the OpenAI API.

## Requirements

- PHP 8.2+
- ext-curl
- ext-json
- Composer

## Installation

```bash
composer install
