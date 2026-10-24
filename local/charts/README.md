# Чарты проекта Mediapulse

Исходники Helm-чартов компонентов приложения:

- `backend/` — API и Worker Mediapulse
- `databases/` — PostgreSQL + Redis
- `secrets/` — Kubernetes Secret из Vault через External Secrets Operator

Инфраструктурные чарты лежат в `local/manifests/` рядом со скачанными манифестами. Kubernetes Dashboard доступен по `kind.izanar.dev` через Traefik и Cloudflare Tunnel; перед публикацией hostname должен быть защищён Cloudflare Access, а сам Dashboard дополнительно требует токен `admin-user`. Чарт Dashboard также создаёт требуемые им секреты `certs`, `csrf` и `key-holder`.

Локальной обёртки-чарта для Argo CD больше нет. Он ставится напрямую из официального Helm-репозитория; в нашем git лежит файл values (`local/manifests/argocd/values.yaml` — переопределения и стандартный Kubernetes Ingress через `extraObjects`). Ingress не зависит от Traefik CRD, которые устанавливаются позже, использует HTTP внутри кластера; публичный URL Argo CD `https://argocd.izanar.dev` защищён Cloudflare Access и HTTPS завершается на Cloudflare.

MetalLB создаётся до Traefik. Его `IPAddressPool` и `L2Advertisement` помечены
Argo CD sync-wave `1`, чтобы сначала установились CRD, webhook и controller,
и только после готовности webhook применялись пользовательские ресурсы.

## Как чарты попадают в кластер

**Git — единственный источник правды.** Кластерные установки идут только из этого репозитория:

1. **Argo CD (основной путь).** Application'ы в `local/argocd/` ссылаются на пути в этом репозитории (`path: local/charts/backend` и т.д.). При пуше изменений чарта Argo CD сам перерендеривает шаблоны из git-чекаута и синкает — никакого helm-реестра в цепочке нет.
2. **Локальная установка Argo CD (bootstrap).** Argo CD ставится напрямую из официального Helm-репозитория с нашим файлом values:
   ```bash
   helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 7.0.0 \
     --namespace argocd --values ../../Mediapulse-Gitops/local/manifests/argocd/values.yaml
   ```
   (это делает `make argocd-up` в Mediapulse-Infra). Нужен доступ в сеть к `argoproj.github.io`.

Дополнительно существует **публикуемая копия** чартов в отдельном репозитории [Izanar/helm-charts](https://github.com/Izanar/helm-charts) — для внешних потребителей (см. «Публикация чартов» ниже). На кластерные установки она не влияет.

## Изменение чарта

```bash
# 1. правка templates/ или values.yaml
# 2. bump версии НЕ делаем вручную — его сделает CI (см. ниже)
# 3. проверка и публикация в git
helm template test local/charts/<имя>          # локальный рендер
git add -A && git commit -m "chart(<имя>): ..." && git push
```

### Пароль PostgreSQL

Helm берёт значения `.Values.*` из `values.yaml` чарта и из переопределений,
переданных при установке. В базе имя пользователя, пароль и имя БД не задаются
в `values.yaml`: Deployment получает их из Kubernetes Secret
`mediapulse-backend-secrets`, который создаёт отдельный чарт `secrets/` через
External Secrets Operator из Vault. Для локального кластера `make all-up`
автоматически инициализирует одноузловый Vault Raft, разблокирует его ключом
из `~/.config/mediapulse/vault/`, загружает значения из `Mediapulse-App/.env`
и создаёт секрет до запуска базы. Root-токен не сохраняется и отзывается
после первоначальной настройки. Bootstrap-файлы локальные — не удаляйте их,
пока используется PVC Vault.

## CI: версионирование чартов (`.github/workflows/charts.yml`)

Версионируются **только чарты приложения** в `local/charts/*` (backend, databases, secrets).
Инфра в `local/manifests/*` и чужие upstream-чарты здесь не трогаем.

| Триггер | Что делает CI |
|---------|---------------|
| Push в `main` с изменениями в `local/charts/**` | `helm lint` + `helm template` всех чартов → сверка образа приложения с GHCR (см. ниже) → patch-bump **только изменённым** чартам → `helm package` (проверка сборки) → коммит бампа |
| Каждые 30 минут (`schedule`) | Опрос GHCR: если `:latest` образа `api` указывает на новый sha — patch-bump чарта `backend` + `appVersion`/`api.tag`/`worker.tag` = новый тег → коммит |

Версия приложения (`appVersion`, теги образов) забирается **самим Gitops из GHCR без PAT**:
workflow логинится в `ghcr.io` штатным `GITHUB_TOKEN` (`packages: read`), тянет
`ghcr.io/izanar/mediapulse-app/api:latest`, читает label
`org.opencontainers.image.revision` (его ставит `docker/metadata-action` в App CI)
и вычисляет тег `sha-<7 символов>`. Условие: репозиторию Mediapulse-Gitops открыт
Actions-доступ к пакетам `api`/`worker` (страница пакета → Package settings →
Manage Actions access → Add repository) либо пакеты публичные.
Чарты `databases` и `secrets` от образов приложения не зависят — их версии растут только при правке самих чартов (образы postgres/redis пиним вручную).

Ручной запуск: Actions → «Charts» → Run workflow (бампнет изменённые чарты).

Для values `argocd` (bootstrap, лежит в `local/manifests/argocd/values.yaml`) после пуша повторите `make argocd-up` в Mediapulse-Infra — Argo CD ещё не управляет собственной установкой.

Если чарт должен уйти и во внешнюю публикацию — скопируйте его в `Izanar/helm-charts` (см. README там):

```bash
cp -a local/charts/<имя> ../helm-charts/charts/
cd ../helm-charts && git add charts/<имя> && git commit -m "release: <имя> <версия>" && git push
```

## Публикация чартов (отдельный репозиторий)

Для **внешних** потребителей (чужие окружения и команды без доступа к этому git-репозиторию) чарты публикуются в [Izanar/helm-charts](https://github.com/Izanar/helm-charts) через [chart-releaser-action](https://github.com/helm/chart-releaser-action):

```bash
helm repo add mediapulse https://izanar.github.io/helm-charts
helm repo update
helm search repo mediapulse/
```

- Исходники чартов остаются здесь; в helm-charts лежит **копия**, которую нужно синхронизировать вручную (команда выше).
- Публикацию запускает push в `main` helm-charts с изменениями в `charts/**`: chart-releaser создаёт GitHub Release с `.tgz` для каждой новой версии и обновляет `index.yaml` в ветке `gh-pages` (GitHub Pages).
- **Версия в `Chart.yaml` обязана расти** при каждом изменении чарта — релизы иммутабельны, повторный пуш той же версии не перезапишет артефакт.
- Кластер по-прежнему синкает Argo CD из этого git-репозитория — публикация ничего не меняет в GitOps-цепочке.
