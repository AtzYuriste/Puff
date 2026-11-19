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

# M1
# Step 1
aws ecr create-repository --repository-name $GROUP-app
git clone --depth 1 https://github.com/traefik/whoami.git app-src
docker build -t $REGISTRY/$GROUP-app:v1 app-src
docker push $REGISTRY/$GROUP-app:v1
aws ecr list-images --repository-name $GROUP-app

# Step 2
VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' --output text)

SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC \
  --query 'Subnets[:2].SubnetId' --output text | tr '\t' ',')

ALB_SG=$(aws ec2 create-security-group --group-name $GROUP-alb-sg \
  --description "ALB" --vpc-id $VPC --query GroupId --output text)
APP_SG=$(aws ec2 create-security-group --group-name $GROUP-app-sg \
  --description "app" --vpc-id $VPC --query GroupId --output text)

aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $APP_SG --protocol tcp --port 80 --cidr 0.0.0.0/0

# Step 3
ALB=$(aws elbv2 create-load-balancer --name $GROUP-alb \
  --subnets ${SUBNETS//,/ } --security-groups $ALB_SG \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

TG=$(aws elbv2 create-target-group --name $GROUP-tg \
  --protocol HTTP --port 80 --target-type ip --vpc-id $VPC --health-check-path / \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 create-listener --load-balancer-arn $ALB --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG

# Step 4
aws ecs create-cluster --cluster-name $GROUP

aws ecs register-task-definition --family $GROUP-app \
  --network-mode awsvpc --requires-compatibilities FARGATE --cpu 256 --memory 512 \
  --container-definitions "[{\"name\":\"app\",\"image\":\"$REGISTRY/$GROUP-app:v1\",\"portMappings\":[{\"containerPort\":80}],\"essential\":true}]"

aws ecs create-service --cluster $GROUP --service-name $GROUP-app \
  --task-definition $GROUP-app --desired-count 1 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$APP_SG],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=$TG,containerName=app,containerPort=80"

# Step 5

aws rds create-db-instance --db-instance-identifier $GROUP-db \
  --engine postgres --db-instance-class db.t3.micro --allocated-storage 20 \
  --master-username app --master-user-password 'ChangeMe-123' \
  --publicly-accessible

aws rds describe-db-instances --db-instance-identifier $GROUP-db \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address,Endpoint.Port]'

# Step 6

echo "<h1>$GROUP is up</h1>" > index.html
aws s3 cp index.html s3://$GROUP-site/

aws s3 website s3://$GROUP-site/ --index-document index.html

aws s3api delete-public-access-block --bucket $GROUP-site

aws s3api put-bucket-policy --bucket $GROUP-site --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::$GROUP-site/*\"}]}"

