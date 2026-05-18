# Quality Gate

Este diretorio concentra a validacao local e os relatorios de qualidade do time de desenvolvimento.

## Rodar localmente

```bash
./dev/scripts/quality-gate.sh
```

Com `mise`, a partir da raiz do repositorio:

```bash
mise run quality
```

## Rodar com Docker

```bash
docker run --rm -v "$PWD:/app" -w /app docker.io/composer:2 ./dev/scripts/quality-gate.sh
```

Com `mise`:

```bash
mise run quality:docker
```

## Relatorios

Os relatorios sao gerados em:

```text
dev/quality/reports/
```

No GitHub Actions, o resumo tambem aparece no `Step Summary` e os arquivos em `dev/quality/reports/` sao publicados como artifact.

## Escopo inicial

- `composer validate`
- `php -l` nos arquivos PHP versionados
- PHPStan `level: 0` em modo informativo

O PHPStan usa a configuracao em:

```text
dev/quality/phpstan.neon
```

Relatorios gerados:

```text
dev/quality/reports/summary.md
dev/quality/reports/php-lint.txt
dev/quality/reports/phpstan/phpstan-summary.txt
dev/quality/reports/phpstan/phpstan.txt
dev/quality/reports/phpstan/phpstan.json
```

Este gate ainda nao e obrigatorio para merge; ele roda em Pull Requests para dar visibilidade inicial sem bloquear o fluxo.

Por padrao, PHPStan roda em modo informativo porque o modulo depende de classes Magento que podem nao estar instaladas no ambiente de CI. Para tornar PHPStan bloqueante no futuro:

```bash
PHPSTAN_ENFORCE=1 ./dev/scripts/quality-gate.sh
```

## Nota sobre dependencias

O projeto depende de `magento/framework`, que normalmente requer acesso ao repositorio Composer da Magento. Por isso, o gate inicial nao executa `composer install` do projeto e baixa uma versao fixa do PHPStan PHAR com verificacao de checksum.
