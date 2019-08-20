#!/bin/sh -ex

# XXX: depends on awscli
# XXX: depends on git
# XXX: depends on docker

usage() {
    local rcode="$1"
    local msg="$2"

    cat <<EOF
Usage: ./build.sh org/repo [gcob:-master]

EOF
    exit $rcode
}

repository() {
    local org_repo="$1"
    local environment="$2"

    local t_org_repo=$(_transliterate "$org_repo")

    if ! aws ecr describe-repositories --repository-names "${t_org_repo}-${environment}" >/dev/null; then
	aws ecr create-repository --repository-name "${t_org_repo}-${environment}"
    else
	echo "$t_org_repo exists already"
    fi
}

clone() {
    local org_repo="$1"
    local workdir="$2"

    git clone https://github.com/${org}/${repo} ${workdir}
}

build() {
    local org_repo="$1"
    local workdir="$2"
    local environment="$3"
    local version="$4"

    local t_org_repo=$(_transliterate "$org_repo")
    (
	cd $workdir
	git checkout $version
	case $environment in
	    production) docker build -f Dockerfile-prod -t ${t_org_repo}-${environment}:${version} . ;;
	    *)          docker build -t ${t_org_repo}-${environment}:${version} . ;;
	esac
    )
}

tag() {
    local org_repo="$1"
    local account_id="$2"
    local region="$3"
    local environment="$4"
    local gh_version="$5"

    local tag=
    case $gh_version in
	master) tag=latest ;;
	*) tag=$gh_version ;;
    esac

    local t_org_repo=$(_transliterate "$org_repo")

    local image_id=$(docker images ${t_org_repo}-${environment} | grep $gh_version | awk '{print $3}')

    docker tag ${image_id} ${account_id}.dkr.ecr.${region}.amazonaws.com/${t_org_repo}-${environment}:${tag}
}

push() {
    local org_repo="$1"
    local account_id="$2"
    local region="$3"
    local environment="$4"

    local t_org_repo=$(_transliterate "$org_repo")

    eval `aws ecr get-login --no-include-email`
    docker push ${account_id}.dkr.ecr.${region}.amazonaws.com/${t_org_repo}-${environment}:latest
}

clean() {
    local workdir="$1"

    if [ x"$workdir" != x"/" -a -n "$workdir" ]; then
	rm -rf "$workdir"
    fi
}

_transliterate() {
    local str="$1"

    echo "$str" | sed -e 's,/,-,g'
}

main() {
    local org_repo="$1"
    local environment="${2:-lab}"
    local gcob="${3:-master}"

    local org=$(echo $org_repo  | cut -d / -f 1)
    local repo=$(echo $org_repo | cut -d / -f 2)

    local workdir=/tmp/docker/${org_repo}

    local account_id=$(aws sts get-caller-identity --output text --query "Account")
    local region=${AWS_DEFAULT_REGION:-us-east-1} # XXX: use meta data service in jenkins

    clean      "$workdir"
    repository "$org_repo" "$environment"
    clone      "$org_repo" "$workdir"
    build      "$org_repo" "$workdir" "$environment" "$gcob"
    tag        "$org_repo" "$account_id" "$region" "$environment" "$gcob"
    push       "$org_repo" "$account_id" "$region" "$environment"
    clean      "$workdir"

    return 0
}

main "$@"
