#!/bin/bash
# Your group's deploy script. Put every command you run here, in order,
# so any member can rebuild your infra from zero on their machine.
set -e
cd "$(dirname "$0")/.." && . ./env.sh
: "${GROUP:?export GROUP=gXX first}"

# M0: IAM
for u in jason yannick zhiqiang melodie; do
  aws iam create-user --user-name $GROUP-$u
done
aws iam create-group --group-name $GROUP-admins
aws iam attach-group-policy --group-name $GROUP-admins \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
for u in jason yannick zhiqiang melodie; do
  aws iam add-user-to-group --group-name $GROUP-admins --user-name $GROUP-$u
done

aws iam create-user --user-name $GROUP-auditor
aws iam put-user-policy --user-name $GROUP-auditor --policy-name read-only \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:List*","s3:Get*","ec2:Describe*"],"Resource":"*"}]}'

# M0: bucket
aws s3api create-bucket --bucket $GROUP-site