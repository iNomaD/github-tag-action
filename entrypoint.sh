#!/bin/bash

# config
default_tag=${DEFAULT_TAG:-0.0.0}
with_v=${WITH_V:-false}
release_branches=${RELEASE_BRANCHES:-master}
custom_tag=${CUSTOM_TAG}

pre_release="true"
IFS=',' read -ra branch <<< "$release_branches"
for b in "${branch[@]}"; do
    echo "Is $b a match for ${GITHUB_REF#'refs/heads/'}"
    if [[ "${GITHUB_REF#'refs/heads/'}" =~ $b ]]
    then
        pre_release="false"
    fi
done
echo "pre_release = $pre_release"

# fetch tags
git fetch --tags

# get latest tag
tag_pattern='*.*.*'
tag=$(git describe --tags `git rev-list --tags=$tag_pattern --max-count=1`)
tag_commit=$(git rev-list -n 1 $tag)
echo "Latest tag: $tag"

# get current commit hash for tag
commit=$(git rev-parse HEAD)

if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Skipping..."
    echo ::set-output name=tag::$tag
    exit 0
fi

# if there are none, start tags at default_tag
if [ -z "$tag" ]
then
    tag=$default_tag
    new=$(semver bump prerel SNAPSHOT $tag)
    log=''
else
    new=$tag
    log=$(git log $tag_commit..HEAD --format='%H')
fi

for i in $log; do
    # get commit message
    message=$(git log --pretty=oneline $i | grep $i)
    echo "New commit: $message"

    # get commit logs and determine home to bump the version
    # supports #major, #minor, #patch, #release
    case "$message" in
        *#major* )
          new=$(semver bump major $new)
          new=$(semver bump prerel SNAPSHOT $new)
          ;;
        *#minor* )
          new=$(semver bump minor $new)
          new=$(semver bump prerel SNAPSHOT $new)
          ;;
        *#patch* )
          new=$(semver bump patch $new)
          new=$(semver bump prerel SNAPSHOT $new)
          ;;
        *#release* )
          new=$(semver bump release $new)
          ;;
    esac
done

# if version was not bumped then increment build number
if [ "$new" == "$tag" ]; then
    # get and increment build number
    # will default to 1 if it was not a number
    build=$(semver get build $tag)
    build=$((build+1))
    new=$(semver bump prerel SNAPSHOT $new)
    new=$(semver bump build `echo $build` $new)
fi

# prefix with 'v'
if $with_v
then
    new="v$new"
fi

if $pre_release
then
    new="$new-${commit:0:7}"
fi

if [ ! -z $custom_tag ]
then
    new="$custom_tag"
fi

echo $new

# set outputs
echo ::set-output name=new_tag::$new
echo ::set-output name=tag::$new

if $pre_release
then
    echo "This branch is not a release branch. Skipping the tag creation."
    exit 0
fi

# push new tag ref to github
dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
full_name=$GITHUB_REPOSITORY
git_refs_url=$(jq .repository.git_refs_url $GITHUB_EVENT_PATH | tr -d '"' | sed 's/{\/sha}//g')

echo "$dt: **pushing tag $new to repo $full_name"

curl -s -X POST $git_refs_url \
-H "Authorization: token $GITHUB_TOKEN" \
-d @- << EOF

{
  "ref": "refs/tags/$new",
  "sha": "$commit"
}
EOF
