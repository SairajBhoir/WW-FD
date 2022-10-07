#!/bin/bash

set -eufo pipefail
AWS_DEFAULT_REGION=us-east-1
accountId=$(aws sts get-caller-identity --query Account --output text)
prefix="arn:aws:codecommit:$AWS_DEFAULT_REGION:$accountId:"

echo "Fetching the account repositories"
repositories=$(aws codecommit list-repositories --region us-east-1 --query repositories[*].repositoryName)
repositoryNames=$(echo "$repositories" | jq -r 'join(",")')
repositoryArns=$(echo "$repositories" | jq -r --arg prefix "$prefix" 'map($prefix+.) | join(",")')

# This isn't supported yet by CloudFormation.
echo "Creating and associating the approval rule"
name=my-default-approval-rule
template="{\"Version\": \"2018-11-08\",\"Statements\": [{\"Type\": \"Approvers\",\"NumberOfApprovalsNeeded\": 2,\"ApprovalPoolMembers\": [\"*\"]}]}"
aws codecommit create-approval-rule-template --approval-rule-template-name $name --approval-rule-template-description "2 approvals for all PRs." --approval-rule-template-content "$template" || true
aws codecommit update-approval-rule-template-content --approval-rule-template-name $name --new-rule-content "$template"
IFS=',' read -ra repositories <<< "$repositoryNames"
for repository in "${repositories[@]}"; do
  aws codecommit associate-approval-rule-template-with-repository --approval-rule-template-name $name --repository-name $repository
done

echo "Deploying the reviewer template."
aws cloudformation deploy --template-file ./reviewer.yml --stack-name reviewer --parameter-overrides TrackedRepositories=$repositoryArns --tags Application=Reviewer --capabilities CAPABILITY_NAMED_IAM

echo "Done."