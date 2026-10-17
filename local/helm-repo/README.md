# Helm-репозиторий проекта Mediapulse

Здесь хранятся упакованные Helm-чарты проекта:
- `backend` — API и Worker Mediapulse
- `databases` — PostgreSQL и Redis
- `argocd` — локальная обёртка над upstream-чартом `argo/argo-cd` (значения проекта + Traefik IngressRoute)

## Подключение репозитория

```bash
helm repo add mediapulse https://izanar.github.io/Mediapulse-Gitops
helm repo update
```

## Установка чартов

```bash
# Бэкенд
helm install mediapulse-backend mediapulse/backend -n default

# Базы данных
helm install mediapulse-databases mediapulse/databases -n default

# Argo CD (обёртка со значениями проекта + IngressRoute)
helm install argocd mediapulse/argocd -n argocd
```

## Сборка репозитория локально

```bash
cd local/
helm package charts/backend --destination helm-repo/
helm package charts/databases --destination helm-repo/
helm package charts/argocd --destination helm-repo/
helm repo index helm-repo --url https://izanar.github.io/Mediapulse-Gitops
```

Чарт `argocd` является обёрткой (umbrella) над `argo/argo-cd`. Upstream-зависимость запакована внутрь чарта (`charts/argo-cd-7.0.0.tgz`), поэтому для установки не нужен доступ к `https://argoproj.github.io/argo-helm`. При обновлении версии зависимости выполните `helm dependency build charts/argocd` перед упаковкой.

## Откуда взялись `.tgz`: как чарты упаковываются

Файлы `.tgz` — не скачанное извне, а **результат локальной упаковки** каталогов из `local/charts/`. Helm-репозиторий — это по определению просто папка, отдаваемая по HTTP: `index.yaml` + архивы чартов. Никакого отдельного сервера не нужно.

**Шаг 1 — `helm package`.** Команда берёт каталог чарта (`Chart.yaml`, `values.yaml`, `templates/`, `charts/`) и кладёт его в tar.gz с префиксом имени чарта и версии из `Chart.yaml`. Упаковывается ровно то, что лежит в git — ничего не скачивается:

```bash
helm package charts/argocd --destination helm-repo/
# Successfully packaged chart and saved it to: helm-repo/argocd-0.2.0.tgz
```

Что внутри архива (`tar -tzf helm-repo/argocd-0.2.0.tgz`):

```
argocd/Chart.yaml              <- манифест обёртки (name: argocd, version: 0.2.0)
argocd/Chart.lock              <- лок версии зависимости
argocd/values.yaml             <- значения (подключаются при helm install автоматически)
argocd/templates/ingress.yaml  <- собственный шаблон IngressRoute
argocd/charts/argo-cd/...      <- upstream-чарт argo-cd 7.0.0, распакованный внутрь (160 файлов)
```

Благодаря каталогу `charts/` внутри пакета `helm install mediapulse/argocd` **ничего не качает** с `argoproj.github.io` — весь argo-cd уже внутри архива.

**Шаг 2 — `helm repo index`.** Команда перечитывает все `.tgz` в папке и (пере)генерирует `index.yaml` — единственный файл, который читает клиент при `helm repo add` / `helm repo update`:

```bash
helm repo index helm-repo --url https://izanar.github.io/Mediapulse-Gitops
```

Для каждой версии в `index.yaml` попадают: версия, appVersion, описание, прямая ссылка на tgz и `digest` — sha256-контента архива. При `helm pull` / `helm install` клиент сверяет digest с скачанным файлом и падает, если файл повреждён или подменён.

**Шаг 3 — публикация.** Workflow [`.github/workflows/helm-pages.yml`](../../.github/workflows/helm-pages.yml) при пуше в `main` (с изменениями в `local/helm-repo/**`) или по ручному запуску копирует содержимое `local/helm-repo/` в GitHub Pages. Pages — обычный статический HTTP-сервер, то есть `https://izanar.github.io/Mediapulse-Gitops/` и есть helm-репозиторий.

**Порядок действий при изменении чарта:**

```bash
cd local/
helm package charts/<имя> --destination helm-repo/   # новый tgz (при росте версии — новый файл)
rm helm-repo/<имя>-<старая-версия>.tgz              # старый архив удалить вручную
helm repo index helm-repo --url https://izanar.github.io/Mediapulse-Gitops
git add -A && git commit -m "chart: ..." && git push # push триггерит деплой Pages
```

Обратите внимание: `helm repo index` индексирует только те tgz, что физически лежат в папке. Если bump-нуть версию в `Chart.yaml` и не удалить старый архив, в `index.yaml` окажутся обе версии (это допустимо — `helm search repo` покажет обе), но в git-репозитории будет копиться мусор.

Если менялась только реализация чарта **без** роста версии, `helm package` перезапишет tgz тем же именем. Это ломает клиентов: у них в закэшированном `index.yaml` останется старый digest, скачанный по той же URL файл не совпадёт с ним — `helm pull`/`helm install` упадут с ошибкой `digest mismatch`. К тому же GitHub Pages кэширует файлы по URL, и старый архив может отдаваться ещё какое-то время. Поэтому **любое изменение чарта требует bump-а версии в `Chart.yaml`** — это обязательное правило.

## Связь с Argo CD

Argo CD Application'ы в `local/argocd/` по-прежнему ссылаются на локальные пути в Git-репозитории (`path: local/charts/backend` и т.д.), а не на удалённый Helm-репозиторий. Helm-репозиторий нужен для распространения чартов вне этого репозитория (например, для установки в другие окружения или через CI/CD).