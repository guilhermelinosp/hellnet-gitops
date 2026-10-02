#!/usr/bin/env bash
# Abre um PR por servico cujo ultimo release no GitHub e mais novo que o newTag em apps/<servico>/kustomization.yaml.
# So considera o release depois que a imagem existe no GHCR (o pipeline cria o release e depois publica a imagem).
# DRY_RUN=1 apenas imprime o que faria. Precisa de: gh (autenticado), docker, git.
set -euo pipefail

OWNER=${OWNER:-guilhermelinosp}
DRY_RUN=${DRY_RUN:-0}
BASE=${BASE:-main}
PREFIX=${BRANCH_PREFIX:-bump}   # so muda em teste

# A imagem existe no GHCR? (consulta anonima ao registry; as imagens sao publicas)
image_exists() {
  local svc=$1 tag=$2 token
  token=$(curl -fsS "https://ghcr.io/token?scope=repository:$OWNER/$svc:pull" | jq -r .token) || return 1
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    "https://ghcr.io/v2/$OWNER/$svc/manifests/$tag")" = 200 ]
}

newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "${1#v}" "${2#v}" | sort -V | tail -1)" = "${1#v}" ]; }

for dir in apps/*/; do
  svc=$(basename "$dir")
  file="$dir/kustomization.yaml"
  current=$(sed -n 's/^ *newTag: *\(v[0-9][^ ]*\).*/\1/p' "$file" | head -1)
  latest=$(gh release view --repo "$OWNER/$svc" --json tagName --jq .tagName 2>/dev/null || true)
  if [ -z "$current" ] || [ -z "$latest" ]; then echo "[$svc] sem tag atual ($current) ou release ($latest): ignorado"; continue; fi
  if ! newer "$latest" "$current"; then echo "[$svc] em dia ($current)"; continue; fi
  if ! image_exists "$svc" "$latest"; then
    echo "[$svc] release $latest ainda sem imagem no GHCR: tento na proxima execucao"; continue
  fi
  branch="$PREFIX/$svc-$latest"
  if [ -n "$(gh pr list --head "$branch" --state all --json number --jq '.[0].number' 2>/dev/null)" ]; then
    echo "[$svc] ja existe PR para $latest"; continue
  fi
  echo "[$svc] $current -> $latest"
  [ "$DRY_RUN" = 1 ] && continue
  git switch -q -c "$branch" "origin/$BASE" 2>/dev/null || git switch -q -C "$branch" "origin/$BASE"
  sed -i.bak "s|newTag: $current|newTag: $latest|" "$file" && rm -f "$file.bak"
  git add "$file"
  git commit -q -m "chore($svc): bump the image to $latest"
  git push -q -u "https://x-access-token:${GH_TOKEN}@github.com/$OWNER/hellnet-gitops.git" "$branch"
  gh pr create --base "$BASE" --head "$branch" \
    --title "chore($svc): bump the image to $latest" \
    --body "Atualiza \`ghcr.io/$OWNER/$svc\` de \`$current\` para \`$latest\` (release: https://github.com/$OWNER/$svc/releases/tag/$latest).

Depois do merge, sincronize no Argo CD: \`argocd app sync $svc\`."
  git switch -q "$BASE"
done
