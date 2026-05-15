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

Este gate ainda nao e obrigatorio para merge; ele roda em Pull Requests para dar visibilidade inicial sem bloquear o fluxo.
