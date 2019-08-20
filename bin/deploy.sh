#!/bin/sh -x

## XXX: needs jq
## XXX: hard codes alb endpoint
## XXX: we'll need three for envs (fun times in terraform)

usage() {
    local rcode="$1"
    local msg="$2"

    cat <<EOF
Usage: bin/depoy.sh [create|update] container_version

EOF
    exit $rcode
}

p6_template_fill_in() {
    local infile="$1"
    local outfile="$2"
    local q_flag="$3"
    shift 3

    cp "$infile" "$outfile"
    local sed_re
    local save_ifs=$IFS
    IFS=^
    for sed_re in $(echo "$@"); do
	if [ x"$q_flag" = x"no_quotes" ]; then
	    sed -i '' -e $sed_re $outfile
	else
	    sed -i '' -e "$sed_re" $outfile
	fi
    done
    IFS=$save_ifs
}

p6_template_fill_args() {
    local mark="$1"
    local sep="$2"
    local split="$3"
    shift 3

    local pair
    local args
    local save_ifs=$IFS
    IFS=$split
    for pair in $(echo $@); do
	local k=$(echo $pair | cut -f 1 -d '=')
	local v=$(echo $pair | cut -f 2- -d '=')

	args="${args}s${sep}${mark}${k}${mark}${sep}${v}${sep}g^"
    done
    IFS=$save_ifs

    echo $args | sed -e 's,\^$,,'
}

_transliterate() {
    local str="$1"

    echo "$str" | sed -e 's,/,-,g'
}

p6_template_process() {
    local infile="$1"
    shift 1

    local t_infile=$(_transliterate "$infile")

    local dir="/tmp/aws.tmpl"
    local outfile="$dir/$t_infile"


    local fill_args=$(p6_template_fill_args "" "," " " "$@")

    mkdir -p $dir
    p6_template_fill_in "share/$infile" "$outfile" "no_quotes" "$fill_args"

    echo $outfile
}

task_definition_register() {
    local org_repo="$1"
    local environment="$2"
    local version="$3"

    local t_org_repo=$(_transliterate "$org_repo")

    local task_definition_file=$(
	p6_template_process "${t_org_repo}.template"\
			    "NAME=${t_org_repo}-${environment}" \
			    "FAMILY=$t_org_repo" \
			    "VERSION=$version"
	  )

    aws ecs register-task-definition \
	--cli-input-json file://$task_definition_file > $task_definition_file.out

    local taskdefinition_arn=$(cat $task_definition_file.out | jq .taskDefinition.taskDefinitionArn | sed -e 's,",,g')

    echo $taskdefinition_arn
}

service_action() {
    local cmd="$1"
    local org_repo="$2"
    local environment="$3"
    local taskdefinition_arn="$4"
    local target_group_arn="$5"

    local t_org_repo=$(_transliterate "$org_repo")

    local service_file=$(
	p6_template_process "service-${cmd}-${t_org_repo}.template" \
			    "NAME=${t_org_repo}-${environment}" \
			    "SERVICE=${t_org_repo}" \
			    "CLUSTER=lab" \
			    "ROLE=/ecs/lab_ecs_lb_role" \
			    "TASKDEFINITION_ARN=$taskdefinition_arn" \
			    "TARGET_GROUP_ARN=$target_group_arn"
			    )
    aws ecs ${cmd}-service --cli-input-json file://$service_file > $service_file.out
}

target_group_arn_get() {
    local name="$1"

    name=$(echo $name | sed -e 's,_.*$,,')
    aws elbv2 describe-target-groups --output text --name $name --query "TargetGroups[].[TargetGroupArn]"
}

main() {
    local cmd="$1"
    local org_repo="$2"
    local environment="$3"
    local lb_name="$4"
    local version="${5:-latest}"
    shift 4

    rm -rf /tmp/aws.tmpl
    local taskdefinition_arn=$(task_definition_register "$org_repo" "$environment" "$version")
    local target_group_arn=$(target_group_arn_get "$lb_name")
    service_action "$cmd" "$org_repo" "$environment" "$taskdefinition_arn" "$target_group_arn"
}

main "$@"
