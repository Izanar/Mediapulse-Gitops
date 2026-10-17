# Чарты проекта Mediapulse

Исходники Helm-чартов:

- `backend/` — API и Worker Mediapulse
- `databases/` — PostgreSQL + Redis
- `argocd/` — обёртка над upstream-чартом `argo/argo-cd` (значения проекта + Traefik IngressRoute)

## Репозиторий чартов (OCI, GitHub Container Registry)

Чарты проекта публикуются как **OCI-пакеты** в GHCR:

```
oci://ghcr.io/izanar/mediapulse-charts
```

Это полноценный Helm-репозиторий нового (современного) формата: реестр сам играет роль index — версии это теги пакетов, `helm pull`/`helm install` ходят напрямую в реестр, никакие `index.yaml` и статические хостинги не нужны.

### Установка

```bash
# Argo CD (обёртка со значениями проекта + IngressRoute)
helm install argocd oci://ghcr.io/izanar/mediapulse-charts/argocd --version 0.2.0 -n argocd

# Бэкенд
helm install mediapulse-backend oci://ghcr.io/izanar/mediapulse-charts/backend --version 0.1.0 -n default

# Базы данных
helm install mediapulse-databases oci://ghcr.io/izanar/mediapulse-charts/databases --version 0.1.0 -n default
```

Анонимный pull работает, пакеты публичные; `helm registry login` нужен только для пуша.

### Как публикуются чарты

Workflow [`.github/workflows/helm-oci.yml`](../../.github/workflows/helm-oci.yml) при пуше в `main` (с изменениями в `local/charts/**`) или по ручному запуску для каждого каталога в `local/charts/` выполняет:

```bash
helm package charts/<имя> --destination /tmp/charts
helm push /tmp/charts/<имя>-<версия>.tgz oci://ghcr.io/izanar/mediapulse-charts
```

`helm package` упаковывает содержимое каталога чарта (`Chart.yaml`, `values.yaml`, `templates/`, `charts/`) в tar.gz с префиксом `имя-версия` — упаковывается ровно то, что лежит в git, ничего не скачивается. Пример внутренней структуры `argocd-0.2.0.tgz`:

```
argocd/Chart.yaml              <- манифест обёртки (name: argocd, version: 0.2.0)
argocd/Chart.lock              <- лок версии зависимости
argocd/values.yaml             <- значения (подключаются при helm install автоматически)
argocd/templates/ingress.yaml  <- собственный шаблон IngressRoute
argocd/charts/argo-cd/...      <- upstream-чарт argo-cd 7.0.0, распакованный внутрь (160 файлов)
```

Благодаря каталогу `charts/` внутри пакета `helm install …/argocd` ничего не качает с `argoproj.github.io` — весь argo-cd уже внутри архива.

Чарт `argocd` — обёртка (umbrella) над `argo/argo-cd`. При обновлении версии зависимости выполните `helm dependency update charts/argocd` перед публикацией.

**Правило:** теги OCI-реестра иммутабельны — повторный пуш той же версии упадёт с ошибкой. Поэтому **любое изменение чарта требует bump-а версии в его `Chart.yaml`**.

### Порядок действий при изменении чарта

```bash
# 1. bump версии в local/charts/<имя>/Chart.yaml
# 2. локальная проверка
helm template test local/charts/<имя>
helm package local/charts/<имя> --destination /tmp/   # опционально
# 3. коммит и пуш — workflow сам запакует и запушит в GHCR
git add -A && git commit -m "chart(<имя>): ..." && git push
```

## ArtifactHub

[ArtifactHub](https://artifacthub.io) — каталог Helm-чартов (поиск, статистика, верификация publisher'а), **не хостинг**: он не хранит архивы, а индексирует реальные репозитории и ссылается на них. Репозиторий проекта регистрируется там с типом **Helm charts (OCI registry)** и URL:

```
oci://ghcr.io/izanar/mediapulse-charts
```

Регистрация выполняется в UI ArtifactHub (нужен аккаунт, привязанный к GitHub-организации/пользователю `Izanar`), после чего Ownership claim: ArtifactHub выдаёт `artifacthub-repo.yml` с UUID — файл публикуется в реестр как OCI-пакет с тегом `artifacthub.io` (см. [официальную инструкцию](https://artifacthub.io/docs/repositories/helm-charts/)). После подтверждения в UI чарты проекта появятся на artifacthub.io.

## Связь с Argo CD

Argo CD Application'ы в `local/argocd/` ссылаются на локальные пути в Git-репозитории (`path: local/charts/backend` и т.д.), а не на OCI-реестр. Репозиторий чартов нужен для распространения чартов вне этого репозитория (другие окружения, CI/CD, каталоги типа ArtifactHub).
