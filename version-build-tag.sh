#!/usr/bin/env bash -x
set -eo pipefail

## PARAMETER: INPUT: ${{ inputs.semver }}
CURRENT=$(yq '.release.current-version' .github/project.yml )
SNAPSHOT=$(yq '.release.snapshot-version' .github/project.yml)
ARTIFACT=$(yq '.jitpack.artifact' .github/project.yml)
GROUP=$(yq '.jitpack.group' .github/project.yml)

if [[ "${RETRY}" == "true" ]]; then
  NEXT=${CURRENT}
  echo "🔹 Retry project version: $NEXT"
elif [[ -z "${INPUT}" ]] || [[ "${INPUT}" == "project" ]]; then
  NEXT=$(yq '.release.next-version' .github/project.yml)
  echo "🔹 Use project version: $CURRENT --> $NEXT"
else
  TMP=$CURRENT
  major=${TMP%%.*}
  TMP=${TMP#$major.}
  minor=${TMP%%.*}
  TMP=${TMP#$minor.}
  patch=${TMP%.*}
  
  case "$INPUT" in
    major)
      NEXT=$(($major+1)).0.0
      echo "🔹 Bump major version: ${major}.${minor}.${patch} --> $NEXT"
    ;;
    minor)
      NEXT=${major}.$(($minor+1)).0
      echo "🔹 Bump minor version: ${major}.${minor}.${patch} --> $NEXT"
    ;;
    patch)
      NEXT=${major}.${minor}.$(($patch+1))
      echo "🔹 Bump patch version: ${major}.${minor}.${patch} --> $NEXT"
    ;;
    *)
      if [[ ! ${INPUT} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf >&2 'Error : %s is not a valid semver.\n' ${INPUT}
        exit 1
      fi
      NEXT=${INPUT}
      echo "🔹 Use specified version: $CURRENT --> $NEXT"
    ;;
  esac
fi

delete_release_and_cleanup_tag() {
  local tag=$1
  echo "🔹 Attempting to delete release and tag $tag"
  gh release delete $tag -y || true
  git tag -d $tag || true
  git push origin :refs/tags/$tag || true
}

if git rev-parse "refs/tags/$NEXT" > /dev/null 2>&1; then
  if [[ "${RETRY}" == "true" ]]; then
    echo "🔹 Retrying release of $NEXT"
    delete_release_and_cleanup_tag $NEXT
  else
    echo "🛑 Tag $NEXT already exists"
    exit 1
  fi
elif [[ "${RETRY}" == "true" ]]; then
    echo "🔹 Retrying release of $NEXT"
    delete_release_and_cleanup_tag $NEXT
fi

# Messy and not maven-y, but whatever.
echo "🔹 Update version to $NEXT"

if [[ -z "${TEXT_REPLACE}" ]]; then
  TEXT_REPLACE=README.md
fi
for x in ${TEXT_REPLACE}; do
  sed -E -i "s|/$CURRENT|/$NEXT|g" "$x"
  sed -E -i "s|-$CURRENT|-$NEXT|g" "$x"
done
sed -E -i 's|<revision>.*</revision>|<revision>'$NEXT'</revision>|' pom.xml
sed -E -i "s|  current-version: .*|  current-version: $NEXT|g" .github/project.yml
sed -E -i "s|  next-version: .*|  next-version: $NEXT|g" .github/project.yml

if grep '<revision>' pom.xml | grep $NEXT; then
  echo "✅ '<revision>' in pom.xml updated to $NEXT"
else
  echo "❌ '<revision>' in pom.xml is $(grep '<revision>' pom.xml)"
  exit 1
fi

./mvnw -B -ntp package -DskipFormat

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "🔹 DRY RUN: skipping tag update"
else
  git status
  git diff
  if git diff --quiet; then
    echo "-- No changes -- "
  else
    git add pom.xml .github/project.yml ${TEXT_REPLACE} ${COMMIT_PATHS}
    git commit -m "🔖 $NEXT"
    git push origin main
  fi

  git tag $NEXT
  git push --tags
fi

echo "current=${CURRENT}" >> $GITHUB_OUTPUT
echo "next=${NEXT}" >> $GITHUB_OUTPUT
echo "snapshot=${SNAPSHOT}" >> $GITHUB_OUTPUT
echo "artifact=${ARTIFACT}" >> $GITHUB_OUTPUT
echo "group=${GROUP}" >> $GITHUB_OUTPUT
