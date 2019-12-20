#!/bin/bash

# config
with_v=${WITH_V:-false}
version_file_path=${VERSION_FILE_PATH:-version}

# get current version
function prop {
    grep "${1}" "$version_file_path"|cut -d'=' -f2
}
major=$(prop 'MAJOR')
minor=$(prop 'MINOR')
patch=$(prop 'PATCH')
prerel=$(prop 'PREREL')
version="$major.$minor.$patch-$prerel"
compare=$(semver compare "$version" "$version")
if [ ! "$compare" == "0" ]; then
    echo "Wrong version $version. Skipping..."
    exit 0
fi

# fetch tags
git fetch --tags

# get latest tag
tag_pattern="$version*"
tag_commit=$(git rev-list --tags="$tag_pattern" --max-count=1)
echo "Latest tagged commit: $tag_commit"
if [ -n "$tag_commit" ]; then
    tag=$(git describe --tags "$tag_commit")
    echo "Latest tag: $tag"
fi

# get current commit hash for tag
commit=$(git rev-parse HEAD)

if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Skipping..."
    echo ::set-output name=tag::"$tag"
    exit 0
fi

# if there are none, start tags at specified version
if [ -z "$tag" ]
then
    new=$version
else
    # get and increment build number
    # will default to 1 if it was not a number
    build=$(semver get build "$tag")
    build=$((build+1))
    new=$(semver bump build $build "$tag")
fi

# prefix with 'v'
if $with_v
then
    new="v$new"
fi

echo "$new"

# set outputs
echo ::set-output name=new_tag::"$new"
echo ::set-output name=tag::"$new"

# push new tag ref to github
dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
full_name=$GITHUB_REPOSITORY
git_refs_url=$(jq .repository.git_refs_url "$GITHUB_EVENT_PATH" | tr -d '"' | sed 's/{\/sha}//g')

echo "$dt: **pushing tag $new to repo $full_name"

curl -s -X POST "$git_refs_url" \
-H "Authorization: token $GITHUB_TOKEN" \
-d @- << EOF

{
  "ref": "refs/tags/$new",
  "sha": "$commit"
}
EOF
